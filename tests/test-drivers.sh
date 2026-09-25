#!/usr/bin/env bash
# The real run-loop.sh end to end, offline: a throwaway git origin (with a
# develop branch holding plugins/dw), a clone for SOURCE_DIR, a copy of
# this harness as its own repo, and fakes for gh (tests/fake-gh.py over a
# JSON board), ssh and claude. What a cycle does is read back off the board
# and the driver's log.
. "$(dirname "$0")/lib.sh"

# --- fixtures
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
mkdir -p "$T/seed/plugins/dw"; echo x > "$T/seed/plugins/dw/README"
git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
git clone -q -b develop "$T/origin.git" "$T/src"
sha="$(git -C "$T/src" rev-parse HEAD)"

mkdir "$T/h"
(cd "$HARNEST" && tar cf - --exclude ./logs --exclude ./.git .) | (cd "$T/h" && tar xf -)
git -C "$T/h" init -q && git -C "$T/h" add -A && git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm h

ln -s "$HARNEST/tests/fake-gh.py" "$T/bin/gh"
printf '#!/usr/bin/env bash\necho "develop @ %s"\n' "${sha:0:9}" > "$T/bin/ssh"
# claude: one well-formed session that changes nothing, unless
# FAKE_CLAUDE_DO holds a command to run first (an agent's action).
cat > "$T/bin/claude" <<'EOS'
#!/usr/bin/env bash
echo "claude $*" | cut -c1-200 >> "$FAKE_CLAUDE_LOG"
[ -z "${FAKE_CLAUDE_DO:-}" ] || eval "$FAKE_CLAUDE_DO" >/dev/null
echo '{"type":"system","subtype":"init","model":"claude-fake"}'
echo '{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.01,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}'
EOS
chmod +x "$T/bin/ssh" "$T/bin/claude"
export FAKE_CLAUDE_LOG="$T/claude-calls" FAKE_GH_LOG="$T/gh-calls"
: > "$FAKE_CLAUDE_LOG"

board() { # board <json for o/r issues>
  printf '{"o/r": %s, "h/r": []}\n' "$1" > "$T/board.json"
}
loop() { # loop <cycles>: run the real driver against the board
  (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r TICKET_OWNER=dkackman \
     SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin" LEAD_TREE="$T/lead" MAX_CYCLES="$1" SLEEP_SECS=0 SESSION_RETRY_PAUSE_SECS=0 \
     ./run-loop.sh) > "$T/loop.out" 2>&1
}
labels_of() { jq -r --arg n "$1" '.["o/r"][] | select((.number|tostring) == $n) | [.labels[].name] | sort | join(",")' "$T/board.json"; }

# --- 1. a GitHub outage: the cycle finishes, nothing runs
board '[{"number": 1, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
FAKE_GH_FAIL=1 loop 1; rc=$?
eq  "outage: the driver finishes the cycle" 0 "$rc"
has "outage: logged, not fatal" "could not" "$(cat "$T/loop.out")"
eq  "outage: no session launched" 0 "$(wc -l < "$FAKE_CLAUDE_LOG" | tr -d ' ')"

# --- 2. a session that changes nothing, twice: the ledger parks it
board '[{"number": 1, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
loop 2; rc=$?
eq  "ledger: the driver exits cleanly" 0 "$rc"
eq  "ledger: one fix session per cycle" 2 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
eq  "ledger: parked with Don after two" "owner:don,status:needs-approval" "$(labels_of 1)"
has "ledger: the park says why" "sessions in a row ended without changing" "$(jq -r '.["o/r"][0].comments[-1].body' "$T/board.json")"

# --- 3. a session that hands off: the tester verifies it the same cycle
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 2, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
FAKE_CLAUDE_DO='case "$*" in *"fix session"*) gh issue edit 2 --repo o/r --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify ;; *"VERIFY session"*) gh issue edit 2 --repo o/r --remove-label status:fixed-pending-verify --add-label status:verified; gh issue close 2 --repo o/r --reason completed ;; esac' \
  loop 1
eq  "hand-off: fix then verify in one cycle" 2 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
eq  "hand-off: closed as verified" "CLOSED" "$(jq -r '.["o/r"][0].state' "$T/board.json")"
eq  "hand-off: no audit warnings" "" "$(grep '\[audit\]' "$T/loop.out" || true)"

# --- 3b. a docs-only fix the tester can't observe: it reroutes, and the
# docs reviewer closes it the same cycle, from the plugin tree
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 4, "state": "OPEN", "labels": [{"name": "owner:tester"}, {"name": "status:fixed-pending-verify"}]}]'
FAKE_CLAUDE_DO='case "$*" in *"VERIFY session"*) gh issue edit 4 --repo o/r --add-label docs-review ;; *"DOCS REVIEW session"*) pwd > "$FAKE_CLAUDE_LOG.cwd"; gh issue edit 4 --repo o/r --remove-label status:fixed-pending-verify --remove-label docs-review --add-label status:reviewed; gh issue close 4 --repo o/r --reason completed ;; esac' \
  loop 1
eq  "docs review: verify, then review, in one cycle" 2 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
eq  "docs review: closed as reviewed" "CLOSED owner:tester,status:reviewed" "$(jq -r '.["o/r"][0].state' "$T/board.json") $(labels_of 4)"
eq  "docs review: runs in the plugin tree" "$(cd "$T/plugin" && pwd -P)" "$(cd "$(cat "$FAKE_CLAUDE_LOG.cwd")" && pwd -P)"
eq  "docs review: no audit warnings" "" "$(grep '\[audit\]' "$T/loop.out" || true)"

# --- 4. an outside filing is parked once, and stays out of the loop
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 3, "state": "OPEN", "author": {"login": "stranger"}, "labels": [{"name": "owner:implementer"}]}]'
loop 1
eq  "external: parked before any session" "owner:don,status:needs-approval" "$(labels_of 3)"
eq  "external: no session ran on it" 0 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"

# --- 5. a feature stage builds only once its plan is specced
: > "$FAKE_CLAUDE_LOG"
plan='"comments": [{"author": {"login": "dkackman"}, "body": "<!-- harnest:plan v1 -->\nplan"}, {"author": {"login": "dkackman"}, "body": "<!-- harnest:decomposed v1 -->"}]'
board "[{\"number\": 10, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"owner:lead\"}, {\"name\": \"status:plan-approved\"}], $plan, \"subIssuesSummary\": {\"total\": 1, \"completed\": 0}},
        {\"number\": 11, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"stage\"}, {\"name\": \"owner:lead\"}], \"parent\": {\"number\": 10}}]"
loop 1
eq  "spec race: no build before specced" 0 "$(grep -c 'BUILD session' "$FAKE_CLAUDE_LOG")"
jq '.["o/r"][0].comments += [{"author": {"login": "dkackman"}, "body": "<!-- harnest:specced v1 -->"}]' "$T/board.json" > "$T/b2" && mv "$T/b2" "$T/board.json"
loop 1
eq  "spec race: builds once specced" 1 "$(grep -c 'BUILD session for stage #11' "$FAKE_CLAUDE_LOG")"

# --- 6. run-features: an idea with owner:lead gets a design session
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 20, "state": "OPEN", "labels": [{"name": "idea"}, {"name": "owner:lead"}]},
        {"number": 21, "state": "OPEN", "labels": [{"name": "feature"}, {"name": "owner:don"}, {"name": "status:plan-review"}]}]'
(cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
   LEAD_TREE="$T/lead" SESSION_RETRY_PAUSE_SECS=0 ./run-features.sh) > "$T/features.out" 2>&1
eq  "features: exits cleanly" 0 $?
eq  "features: one design session, for the idea" 1 "$(grep -c 'DESIGN session for issue #20' "$FAKE_CLAUDE_LOG")"
eq  "features: none for the issue with Don" 0 "$(grep -c '#21' "$FAKE_CLAUDE_LOG")"

# --- 6b. run-loop runs the design queue itself (features_pass), unless told not to
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 22, "state": "OPEN", "labels": [{"name": "idea"}, {"name": "owner:lead"}]}]'
LEAD_DESIGN_IN_LOOP=0 loop 1
eq  "loop design: off leaves it alone" 0 "$(grep -c 'DESIGN session' "$FAKE_CLAUDE_LOG")"
loop 1
eq  "loop design: the cycle designs the idea" 1 "$(grep -c 'DESIGN session for issue #22' "$FAKE_CLAUDE_LOG")"
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 1, "state": "OPEN", "labels": [{"name": "owner:tester"}, {"name": "status:needs-info"}]}]'
loop 1
eq  "loop design: nothing waiting, run-features not started" "" "$(grep 'feature run\|no feature waiting' "$T/loop.out" || true)"

# --- 7. run-regression: a two-case override suite, one case per session
: > "$FAKE_CLAUDE_LOG"
cat > "$T/h/regression-suite-tiny.md" <<'EOS'
# tiny suite
## Fixtures
none
### S-F001 — first
steps
### S-F002 — second
steps
EOS
(cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
   PLUGIN_TREE="$T/plugin" CASES_PER_SESSION=1 SESSION_RETRY_PAUSE_SECS=0 ./run-regression.sh smoke regression-suite-tiny.md) > "$T/reg.out" 2>&1
eq  "regression: exits cleanly" 0 $?
eq  "regression: two chunks and a sweep" 3 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "regression: chunk sessions are labelled" "[regression:smoke.2] usage:" "$(cat "$T/reg.out")"

# --- 8. run-curate: a forced audit of one level runs one session
: > "$FAKE_CLAUDE_LOG"
(cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r CURATE_FORCE=1 \
   SESSION_RETRY_PAUSE_SECS=0 ./run-curate.sh smoke) > "$T/curate.out" 2>&1
eq  "curate: exits cleanly" 0 $?
eq  "curate: one audit session" 1 "$(grep -c 'AUDIT session' "$FAKE_CLAUDE_LOG")"

# --- 9. run-retro: one session over the evidence
: > "$FAKE_CLAUDE_LOG"
(cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r \
   SESSION_RETRY_PAUSE_SECS=0 ./run-retro.sh) > "$T/retro.out" 2>&1
eq  "retro: exits cleanly" 0 $?
eq  "retro: one session" 1 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
for f in loop features reg curate retro; do cp "$T/$f.out" "/tmp/claude-501/last-$f.out" 2>/dev/null; done
finish
