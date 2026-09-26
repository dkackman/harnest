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
eq  "ledger: parked with Don after two (lem's claim stays)" "owner:don,status:needs-approval,target:lem" "$(labels_of 1)"
has "ledger: the park says why" "sessions in a row ended without changing" "$(jq -r '.["o/r"][0].comments[-1].body' "$T/board.json")"

# --- 3. a session that hands off: the tester verifies it the same cycle
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 2, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
FAKE_CLAUDE_DO='case "$*" in *"fix session"*) gh issue edit 2 --repo o/r --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify ;; *"VERIFY session"*) gh issue edit 2 --repo o/r --remove-label status:fixed-pending-verify --add-label status:verified; gh issue close 2 --repo o/r --reason completed ;; esac' \
  loop 1
eq  "hand-off: fix then verify in one cycle" 2 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
eq  "hand-off: closed as verified" "CLOSED" "$(jq -r '.["o/r"][0].state' "$T/board.json")"
eq  "hand-off: no audit warnings" "" "$(grep '\[audit\]' "$T/loop.out" || true)"
has "lem loop: makes sure its claim label exists" "gh label create target:lem --repo o/r" "$(cat "$T/gh-calls")"
has "lem loop: and the backend labels its prompts file with" "gh label create backend:shared --repo o/r" "$(cat "$T/gh-calls")"

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

# --- 3c. stop-after-cycle: the loop finishes the cycle it is in, then exits,
# and consumes the file so the next start runs normally
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 5, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
mkdir -p "$T/h/logs" && touch "$T/h/logs/stop-after-cycle"
FAKE_CLAUDE_DO='' loop 5
eq  "stop file: one cycle, not five" 1 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "stop file: says why it stopped" "stop-after-cycle found" "$(cat "$T/loop.out")"
eq  "stop file: consumed" "gone" "$([ -e "$T/h/logs/stop-after-cycle" ] && echo present || echo gone)"

# --- 3d. a release freeze: only the release-blocker gets a session, and the
# standing task is held even on a cycle it is due
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 30, "state": "OPEN", "title": "Release 0.5.0", "labels": [{"name": "release"}, {"name": "owner:don"}]},
        {"number": 31, "state": "OPEN", "labels": [{"name": "owner:implementer"}]},
        {"number": 32, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "release-blocker"}]}]'
FAKE_CLAUDE_DO='' TESTER_TASK_EVERY=1 loop 1
eq  "freeze: one session, the blocker's" 1 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "freeze: it was #32's" "implementer:#32" "$(grep '^=== ' "$T/loop.out")"
has "freeze: the standing task is held" "[tester:task] held: release freeze #30 Release 0.5.0" "$(cat "$T/loop.out")"
has "freeze: the board says so" "release freeze #30 Release 0.5.0: only release-blocker issues move" "$(cat "$T/loop.out")"

# --- 3e. run-release.sh: freeze, check, the gates' lock refusal, accept,
# status, and cut refusing without its gates. (pr/run/release/workflow have
# no fake: the CI and preflight gates, review, notes and cut's GitHub steps
# are not exercised here.)
git -C "$T/seed" push -q origin HEAD:master 2>/dev/null
git -C "$T/src" fetch -q origin
rel() { (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman \
          SOURCE_DIR="$T/src" RELEASE_TREE="$T/reltree" ./run-release.sh "$@") > "$T/rel.out" 2>&1; }
board '[{"number": 50, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
rel 0.9.0 freeze
eq  "release: freeze opens the release issue as Don's" "owner:don,release" "$(labels_of 51)"
rel 0.9.0 check; rc=$?
eq  "release: check passes while non-blockers are held" 0 "$rc"
has "release: check records its marker" "harnest:release-gate check $sha pass" "$(jq -r '.["o/r"][] | select(.number == 51) | .comments[].body' "$T/board.json")"
jq '.["o/r"] += [{"number": 52, "state": "OPEN", "labels": [{"name": "owner:tester"}, {"name": "status:fixed-pending-verify"}, {"name": "release-blocker"}]}]' "$T/board.json" > "$T/b2" && mv "$T/b2" "$T/board.json"
rel 0.9.0 check; rc=$?
eq  "release: check fails with a blocker awaiting verification" 1 "$rc"
has "release: and names it" "#52 waits on verification" "$(cat "$T/rel.out")"
mkdir -p "$T/h/logs/.driver.lock" && echo "$$ run-loop" > "$T/h/logs/.driver.lock/owner"
rel 0.9.0 gates ci; rc=$?
rm -rf "$T/h/logs/.driver.lock"
eq  "release: gates refuse while the loop holds the lock" 1 "$rc"
has "release: and say how to stop it" "stop-after-cycle" "$(cat "$T/rel.out")"
# the regression gate: a backend:mps regression filed (and claimed) by the Mac during
# the gate blocks it like any other (Don, 2026-09-26)
: > "$FAKE_CLAUDE_LOG"
FAKE_CLAUDE_DO='[ -e "$T/mps-filed" ] || { touch "$T/mps-filed"; gh issue create --repo o/r --title "S-F034 fails on mps" --label regression,backend:mps,owner:implementer,target:local >/dev/null; }' \
  RELEASE_REGRESSION_LEVELS=smoke rel 0.9.0 gates regression; rc=$?
eq  "release gate: a backend:mps regression fails it" 1 "$rc"
has "release gate: and is listed" "S-F034 fails on mps" "$(jq -r '.["o/r"][] | select(.number == 51) | .comments[].body' "$T/board.json")"
rel 0.9.0 accept regression "suite drift only"
has "release: accept records Don's decision" "harnest:release-gate regression $sha accepted" "$(jq -r '.["o/r"][] | select(.number == 51) | .comments[].body' "$T/board.json")"
rel 0.9.0 status
has "release: status shows the accepted gate" "regression  accepted" "$(cat "$T/rel.out")"
has "release: and the failed check" "check       fail" "$(cat "$T/rel.out")"
# review: the driver files the public findings and keeps security ones local
FAKE_CLAUDE_DO='out="$(printf "%s" "$*" | sed -n "s/.*to exactly this file: \([^ ]*json\).*/\1/p")"; case "$out" in *review-security-*) echo "[{\"area\":\"security\",\"severity\":\"blocker\",\"security\":true,\"title\":\"token-free path leak\",\"file\":\"app.py:1\",\"detail\":\"d\"}]" > "$out" ;; *review-engine-*) echo "[{\"area\":\"engine\",\"severity\":\"blocker\",\"security\":false,\"title\":\"cache never shrinks\",\"file\":\"c.py:2\",\"detail\":\"d\"},{\"area\":\"engine\",\"severity\":\"follow-up\",\"security\":false,\"title\":\"slow save\",\"file\":\"r.py:3\",\"detail\":\"d\"}]" > "$out" ;; *) echo "[]" > "$out" ;; esac' \
  rel 0.9.0 review; rc=$?
eq  "release review: completes" 0 "$rc"
eq  "release review: the public blocker is a release-blocker" "owner:implementer,release-blocker" \
  "$(jq -r '.["o/r"][] | select(.title == "[engine] cache never shrinks") | [.labels[].name] | sort | join(",")' "$T/board.json")"
eq  "release review: the follow-up is plain" "owner:implementer" \
  "$(jq -r '.["o/r"][] | select(.title == "[engine] slow save") | [.labels[].name] | sort | join(",")' "$T/board.json")"
eq  "release review: the security finding never reaches the tracker" "" \
  "$(jq -r '.["o/r"] | .. | strings | select(test("token-free path leak"))' "$T/board.json")"
eq  "release review: it is a private draft advisory" "0.9.0 review: token-free path leak|high|draft" \
  "$(jq -r '.["o/r#advisories"][] | "\(.summary)|\(.severity)|\(.state)"' "$T/board.json")"
has "release review: and blocks as the security gate" "harnest:release-gate security $sha fail" \
  "$(jq -r '.["o/r"][] | select(.number == 51) | .comments[].body' "$T/board.json")"
FAKE_CLAUDE_DO=''
rel 0.9.0 cut --next 0.10.0; rc=$?
eq  "release: cut refuses without its gates" 1 "$rc"
has "release: naming what is missing" "check ci preflight security" "$(cat "$T/rel.out")"

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
has "regression: the level header names lem's commit" "target=lem, head=develop @ " "$(grep 'regression run (' "$T/h/logs/loop.log" | tail -1)"
has "regression: chunk sessions are labelled" "[regression:smoke.2] usage:" "$(cat "$T/reg.out")"

# --- 7b. run-regression against a local server (harnest#15), with the
# loop's lock held: it must not wait on lem's
: > "$FAKE_CLAUDE_LOG"
printf '#!/usr/bin/env bash\necho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "$(hostname)" > "$T/bin/curl"; chmod +x "$T/bin/curl"
mkdir "$T/h/logs/.driver.lock"; echo "$$ run-loop" > "$T/h/logs/.driver.lock/owner"
reg_local() {
  (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
     PLUGIN_TREE="$T/plugin-untouched" DW_TARGET=local DW_LOCAL_DIR="$T/src" CASES_PER_SESSION=0 SESSION_RETRY_PAUSE_SECS=0 \
     FAKE_CLAUDE_DO='printf "%s" "$2" > "$FAKE_PROMPT"; printf "%s\n" "$@" > "$FAKE_PROMPT.args"; echo "${HARNEST_TARGET:-unset}" > "$FAKE_PROMPT.target"' FAKE_PROMPT="$T/local-prompt" \
     ./run-regression.sh smoke regression-suite-tiny.md) > "$T/reg-local.out" 2>&1
}
echo "dirty" >> "$T/h/regression-suite-tiny.md"   # a lem-side edit in progress
echo "develop @ ${sha:0:7}" > "$T/h/logs/.deployed.local"   # what the last local deploy recorded
before_head="$(git -C "$T/h" rev-parse HEAD)"
reg_local
eq  "regression local: runs while lem's lock is held" 0 $?
eq  "regression local: one whole-level session" 1 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "regression local: header names the target and its checkout" "target=local, head=develop @ " "$(grep 'regression run (' "$T/h/logs/loop.local.log" | tail -1)"
sysprompt="$(cat "$T/h/logs/.prompt.regression.local.whole.md")"
has "regression local: prompt names the server it asked" "the local server (mps on $(hostname)) is running develop @ " "$(cat "$T/local-prompt")"
has "regression local: system prompt moves perf history" "regression-perf/local/<case>.jsonl" "$sysprompt"
has "regression local: system prompt files for the implementer with a backend" "\`owner:implementer\` and \`backend:mps\`" "$sysprompt"
has "regression local: system prompt forbids suite edits" "The suite files. Every case in them runs on lem" "$sysprompt"
eq  "regression local: the guard is told the target" "local" "$(cat "$T/local-prompt.target")"
has "regression local: skip and differ counts are logged" "case(s) skipped" "$(cat "$T/reg-local.out")"
eq  "regression local: no suite commit on a local run" "$before_head" "$(git -C "$T/h" rev-parse HEAD)"
has "regression local: header tags the level for the curator" "level=smoke.local," "$(grep 'regression run (' "$T/h/logs/loop.local.log" | tail -1)"
has "regression local: sessions are labelled for retro" "[regression-local:smoke] usage:" "$(cat "$T/reg-local.out")"
has "regression local: the note names the accelerator once" "the local server (mps on $(hostname), http://localhost:8765/mcp)" "$sysprompt"
has "regression local: plugin is the local checkout's" "--plugin-dir
$T/src/plugins/dw" "$(cat "$T/local-prompt.args")"
ok  "regression local: its own log" test -s "$T/h/logs/regression.local.log"
eq  "regression local: lem's plugin tree is never created" "" "$(ls -d "$T/plugin-untouched" 2>/dev/null)"
eq  "regression local: the lem lock is left as it was" "$$ run-loop" "$(cat "$T/h/logs/.driver.lock/owner")"
# memory-heavy cases are never handed out on another server
cat > "$T/h/regression-suite-tinymem.md" <<'EOM'
# tiny suite with a memory-heavy case
## Fixtures
none
### S-F001 — first
steps
### S-F079 — 8192 squared
steps
EOM
: > "$FAKE_CLAUDE_LOG"
(cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
   DW_TARGET=local DW_LOCAL_DIR="$T/src" CASES_PER_SESSION=1 SESSION_RETRY_PAUSE_SECS=0 \
   ./run-regression.sh smoke regression-suite-tinymem.md) > "$T/reg-mem.out" 2>&1
eq  "regression local: held-back case runs no session (one chunk + sweep)" 2 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "regression local: the held-back case is logged as skipped" "REGRESSION-SKIP: S-F079 memory" "$(cat "$T/reg-mem.out")"
has "regression local: and counted" "1 case(s) skipped" "$(cat "$T/reg-mem.out")"
eq  "regression local: only S-F001 is handed out" "" "$(grep 'session .*: .*S-F079' "$T/h/logs/loop.local.log" || true)"
rm -rf "$T/h/logs/.driver.lock"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
: > "$FAKE_CLAUDE_LOG"
reg_local
eq  "regression local: no server answering stops it" 1 $?
has "regression local: and says so" "no dw server answering at http://localhost:8765/mcp" "$(cat "$T/reg-local.out")"
eq  "regression local: before any session" 0 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
rm -f "$T/bin/curl"
(cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin" DW_TARGET=local DW_LOCAL_DIR="$T/nope" MAX_CYCLES=1 ./run-loop.sh) > "$T/loop-local.out" 2>&1
eq  "loop local: refuses without a serving clone" 1 $?
has "loop local: and says why" "DW_LOCAL_DIR is not a git checkout" "$(cat "$T/loop-local.out")"

# --- 10. the loop on the local server (harnest#15 part 2): its own lock,
# log and clones; it claims what it works, leaves lem's and cuda issues
# alone, deploys with the serving clone's deploy.sh, never ssh
printf '#!/usr/bin/env bash\necho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "$(hostname)" > "$T/bin/curl"; chmod +x "$T/bin/curl"
git clone -q -b develop "$T/origin.git" "$T/serve"
mkdir -p "$T/serve/scripts"
deploy_stub() { printf '#!/usr/bin/env bash\necho "deploy $*" >> "%s"\nexit %s\n' "$T/deploys" "$1" > "$T/serve/scripts/deploy.sh"; chmod +x "$T/serve/scripts/deploy.sh"; }
deploy_stub 0
printf '#!/usr/bin/env bash\necho "ssh $*" >> "%s"\n' "$T/ssh-calls" > "$T/bin/ssh-local"; chmod +x "$T/bin/ssh-local"
local_loop() {
  (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r TICKET_OWNER=dkackman \
     DW_TARGET=local DW_LOCAL_DIR="$T/serve" SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin-mps" LEAD_TREE="$T/lead-mps" \
     MAX_CYCLES=1 SLEEP_SECS=0 SESSION_RETRY_PAUSE_SECS=0 "$@" ./run-loop.sh) > "$T/loop-local.out" 2>&1
}
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 30, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:shared"}]},
        {"number": 31, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:cuda"}]},
        {"number": 32, "state": "OPEN", "labels": [{"name": "owner:tester"}, {"name": "status:fixed-pending-verify"}]},
        {"number": 33, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "target:lem"}]}]'
mkdir "$T/h/logs/.driver.lock"; echo "$$ run-loop" > "$T/h/logs/.driver.lock/owner"   # lem's loop, live
rm -f "$T/h/logs/.deployed.local"   # no local deploy on record yet
local_loop TESTER_TASK_EVERY=1 FAKE_CLAUDE_DO='printf "%s\n" "$@" > "$FAKE_PROMPT.args"; echo "${HARNEST_TARGET:-unset}/${HARNEST_ROLE:-unset}" >> "$FAKE_PROMPT.env"' FAKE_PROMPT="$T/local-loop"
eq  "local loop: runs beside lem's lock" 0 $?
eq  "local loop: claims the shared issue" "backend:shared,owner:implementer,target:local" "$(labels_of 30)"
eq  "local loop: leaves the cuda issue alone" "backend:cuda,owner:implementer" "$(labels_of 31)"
eq  "local loop: leaves lem's claim alone" "owner:implementer,target:lem" "$(labels_of 33)"
eq  "local loop: one session, the shared fix (lem's hand-off waits)" 1 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "local loop: the prompt names the local server" "the local server (mps on $(hostname)) is running: " "$(cat "$T/local-loop.args")"
has "local loop: the implementer's settings are the local ones" "agent-settings/implementer.local.json" "$(cat "$T/local-loop.args")"
has "local loop: deploy command in the system prompt" "DW_DIR=$T/serve " "$(cat "$T/h/logs/.prompt.implementer.local.fix.md")"
eq  "local loop: the guard is told" "local/implementer" "$(head -1 "$T/local-loop.env")"
ok  "local loop: its own log" test -s "$T/h/logs/loop.local.log"
ok  "local loop: its own implementer log" test -s "$T/h/logs/implementer.local.log"
has "local loop: shared passes stay with lem's loop" "skipping: lem's loop runs it" "$(cat "$T/h/logs/loop.local.log")"
has "local loop: no standing task" "standing task: lem only" "$(cat "$T/h/logs/loop.local.log")"
eq  "local loop: lem's lock untouched" "$$ run-loop" "$(cat "$T/h/logs/.driver.lock/owner")"
has "local loop: with no deploy on record, it deploys develop" "deploy develop" "$(cat "$T/deploys" 2>/dev/null)"
has "local loop: and records it" "develop @ " "$(cat "$T/h/logs/.deployed.local")"
rm -rf "$T/h/logs/.driver.lock"
# tie: lem's claim lands in the same moment; the Mac yields
board '[{"number": 40, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:shared"}]}]'
: > "$FAKE_CLAUDE_LOG"
local_loop FAKE_GH_ON_EDIT_40=target:lem
eq  "tie: no session on the Mac" 0 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
eq  "tie: lem keeps it" "backend:shared,owner:implementer,target:lem" "$(labels_of 40)"
# the recorded deploy is behind develop: the driver deploys develop, locally
: > "$T/deploys"; echo "develop @ 0000000" > "$T/h/logs/.deployed.local"
board '[{"number": 41, "state": "OPEN", "labels": [{"name": "owner:tester"}, {"name": "status:fixed-pending-verify"}, {"name": "target:local"}]}]'
: > "$FAKE_CLAUDE_LOG"
local_loop
has "deploy: the develop check deploys locally" "deploy develop" "$(cat "$T/deploys" 2>/dev/null)"
eq  "deploy: never over ssh" "" "$(grep 'ssh' "$T/loop-local.out" | grep -v 'no ssh' || true)"
eq  "deploy: the claimed hand-off is verified here" 1 "$(grep -c 'VERIFY session' "$FAKE_CLAUDE_LOG")"
# a failed deploy is logged, and the tester still runs
deploy_stub 1
: > "$FAKE_CLAUDE_LOG"; echo "develop @ 0000000" > "$T/h/logs/.deployed.local"
local_loop
has "deploy fails: logged" "driver deploy of develop failed" "$(cat "$T/h/logs/loop.local.log")"
eq  "deploy fails: the tester still verifies" 1 "$(grep -c 'VERIFY session' "$FAKE_CLAUDE_LOG")"
deploy_stub 0
# no server answering: the loop deploys the serving clone, then checks it
rm -f "$T/h/logs/.deployed.local" "$T/up"
printf '#!/usr/bin/env bash\n[ -e "%s" ] || exit 7\necho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "$T/up" "$(hostname)" > "$T/bin/curl"
printf '#!/usr/bin/env bash\necho "deploy $*" >> "%s"\ntouch "%s"\n' "$T/deploys" "$T/up" > "$T/serve/scripts/deploy.sh"
board '[]'
local_loop
eq  "bootstrap: the loop starts with no server up" 0 $?
has "bootstrap: by deploying the serving clone" "no server answering" "$(cat "$T/h/logs/loop.local.log")"
printf '#!/usr/bin/env bash\necho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "$(hostname)" > "$T/bin/curl"
deploy_stub 0
# closures: the Mac tester answers only closures it holds; lem's skip them
board '[{"number": 60, "state": "CLOSED", "labels": [{"name": "owner:tester"}, {"name": "wontfix"}, {"name": "target:local"}]},
        {"number": 61, "state": "CLOSED", "labels": [{"name": "owner:tester"}, {"name": "wontfix"}]}]'
: > "$FAKE_CLAUDE_LOG"
: > "$T/prompts"
local_loop FAKE_CLAUDE_DO='printf "%s\n" "$2" >> "'"$T"'/prompts"'
has "closures: the Mac takes its own" "CLOSURES session for #60 only" "$(cat "$T/prompts")"
eq  "closures: not lem's" "" "$(grep 'CLOSURES session' "$T/prompts" | grep '#61' || true)"
: > "$T/prompts"
FAKE_CLAUDE_DO='printf "%s\n" "$2" >> "'"$T"'/prompts"' loop 1
has "closures: lem takes its own" "CLOSURES session for #61 only" "$(cat "$T/prompts")"
# a Mac regression run waits on the Mac loop's lock, not lem's
mkdir "$T/h/logs/.driver.lock.local"; echo "$$ run-loop" > "$T/h/logs/.driver.lock.local/owner"
(cd "$T/h" && exec env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
   DW_TARGET=local DW_LOCAL_DIR="$T/serve" CASES_PER_SESSION=0 ./run-regression.sh smoke regression-suite-tiny.md) > "$T/reg-wait.out" 2>&1 &
regpid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q waiting "$T/reg-wait.out" 2>/dev/null && break; sleep 1; done
kill "$regpid" 2>/dev/null; wait "$regpid" 2>/dev/null
has "regression waits on the Mac loop" "waiting for '$$ run-loop'" "$(cat "$T/reg-wait.out")"
rm -rf "$T/h/logs/.driver.lock.local"; rm -f "$T/bin/curl"

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
