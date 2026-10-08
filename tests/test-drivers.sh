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

# --- 3b2. an architecture review (stage C): a hand-off whose session moved
# develop under dw/ is queued for the reviewer by the driver, reviewed from
# the plugin tree against the map as it stands there, then verified. The
# map reaches the reviewer only through its tree, never its prompt.
printf '# Architecture: the seam map\n| Concept | Owner |\n| SENTINEL-ROW | dw/owner.py |\n' > "$T/seed/docs-ARCH.tmp"
git -C "$T/seed" pull -q origin develop 2>/dev/null; mkdir -p "$T/seed/docs"; mv "$T/seed/docs-ARCH.tmp" "$T/seed/docs/ARCHITECTURE.md"
git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm map; git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
export SHIP='git pull -q origin develop 2>/dev/null; mkdir -p dw; echo "$RANDOM" >> dw/owner.py; git add -A; git -c user.name=t -c user.email=t@t commit -qm "fix: #$N"; git push -q origin HEAD:develop 2>/dev/null; gh issue edit $N --repo o/r --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify'
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 6, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
FAKE_CLAUDE_DO='case "$*" in *"fix session"*) N=6; eval "$SHIP" ;; *"ARCHITECTURE REVIEW session"*) pwd > "$FAKE_CLAUDE_LOG.cwd"; grep -c SENTINEL-ROW docs/ARCHITECTURE.md > "$FAKE_CLAUDE_LOG.map"; gh issue edit 6 --repo o/r --remove-label arch-review ;; *"VERIFY session"*) gh issue edit 6 --repo o/r --remove-label status:fixed-pending-verify --add-label status:verified; gh issue close 6 --repo o/r --reason completed ;; esac' \
  loop 1
eq  "arch review: fix, review, verify in one cycle" "implementer:#6 reviewer:#6 tester:#6" "$(grep '^=== ' "$T/loop.out" | sed 's/.*cycle 1: \([a-z]*:#[0-9]*\).*/\1/' | tr '\n' ' ' | sed 's/ $//')"
has "arch review: the driver queued it, naming the range" "<!-- harnest:arch-review " "$(jq -r '.["o/r"][0].comments[].body' "$T/board.json")"
eq  "arch review: then verified and closed" "CLOSED owner:tester,status:verified,target:lem" "$(jq -r '.["o/r"][0].state' "$T/board.json") $(labels_of 6)"
eq  "arch review: runs in the plugin tree" "$(cd "$T/plugin" && pwd -P)" "$(cd "$(cat "$FAKE_CLAUDE_LOG.cwd")" && pwd -P)"
eq  "arch review: the fixture map is there, read at run time" 1 "$(cat "$FAKE_CLAUDE_LOG.map")"
has "arch review: its system prompt points at the map" "docs/ARCHITECTURE.md" "$(cat "$T/h/logs/.prompt.reviewer.arch.md")"
fails "arch review: and never inlines it" grep -q SENTINEL-ROW "$T/h/logs/.prompt.reviewer.arch.md" "$FAKE_CLAUDE_LOG"
eq  "arch review: no audit warnings" "" "$(grep '\[audit\]' "$T/loop.out" || true)"
# a finding bounces it to the implementer, and the tester never sees it
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 7, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
FAKE_CLAUDE_DO='case "$*" in *"fix session"*) N=7; eval "$SHIP" ;; *"ARCHITECTURE REVIEW session"*) gh issue edit 7 --repo o/r --remove-label arch-review --remove-label status:fixed-pending-verify --remove-label owner:tester --add-label owner:implementer ;; esac' \
  loop 1
eq  "arch review bounce: no verify" 0 "$(grep -c 'VERIFY session' "$FAKE_CLAUDE_LOG")"
eq  "arch review bounce: back with the implementer" "owner:implementer,target:lem" "$(labels_of 7)"
# a hand-off that moved nothing under dw/ or dw_mcp/ goes straight to the tester
: > "$FAKE_CLAUDE_LOG"
board '[{"number": 8, "state": "OPEN", "labels": [{"name": "owner:implementer"}]}]'
FAKE_CLAUDE_DO='case "$*" in *"fix session"*) git pull -q origin develop 2>/dev/null; echo y >> plugins/dw/README; git add -A; git -c user.name=t -c user.email=t@t commit -qm "fix: #8"; git push -q origin HEAD:develop 2>/dev/null; gh issue edit 8 --repo o/r --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify ;; esac' \
  loop 1
eq  "no dw/ change: no review, verified directly" "0 1" "$(grep -c 'ARCHITECTURE REVIEW' "$FAKE_CLAUDE_LOG") $(grep -c 'VERIFY session' "$FAKE_CLAUDE_LOG")"
# what follows expects lem, the seed and origin/develop on one commit
git -C "$T/seed" pull -q origin develop 2>/dev/null; git -C "$T/src" fetch -q origin
sha="$(git -C "$T/src" rev-parse origin/develop)"
printf '#!/usr/bin/env bash\necho "develop @ %s"\n' "${sha:0:9}" > "$T/bin/ssh"

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
rel() { (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r TICKET_OWNER=dkackman \
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
# lem behind develop (the notes merge moved it): check deploys develop when
# no loop is running, and leaves it to the loop when one is
cp "$T/bin/ssh" "$T/ssh.saved"
printf '#!/usr/bin/env bash\ncase "$*" in *deploy.sh*) touch "%s"; exit 0 ;; esac\n[ -e "%s" ] && echo "develop @ %s" || echo "develop @ 0000000"\n' \
  "$T/lem-deployed" "$T/lem-deployed" "${sha:0:9}" > "$T/bin/ssh"
mkdir -p "$T/h/logs/.driver.lock" && echo "$$ run-loop" > "$T/h/logs/.driver.lock/owner"
rel 0.9.0 check
rm -rf "$T/h/logs/.driver.lock"
has "release: lem behind is a check problem" "lem runs develop @ 0000000" "$(cat "$T/rel.out")"
eq  "release: and a running loop is left to deploy it" "" "$(ls "$T/lem-deployed" 2>/dev/null)"
rel 0.9.0 check
ok  "release: with no loop running, check deploys develop" test -e "$T/lem-deployed"
eq  "release: and lem then counts as on develop" "" "$(grep 'lem runs develop @ 0000000,' "$T/rel.out" | grep -v 'deploying develop' || true)"
mv "$T/ssh.saved" "$T/bin/ssh"; rm -f "$T/lem-deployed"
# the regression gate: a backend:mps regression filed (and claimed) by the Mac during
# the gate blocks it like any other (Don, 2026-09-26)
: > "$FAKE_CLAUDE_LOG"
FAKE_CLAUDE_DO="cat '$T/h/logs/.driver.lock/owner' >> '$T/lock-seen' 2>/dev/null; "'[ -e "$T/mps-filed" ] || { touch "$T/mps-filed"; gh issue create --repo o/r --title "S-F034 fails on mps" --label regression,backend:mps,owner:implementer,target:mini-ai >/dev/null; }' \
  RELEASE_REGRESSION_LEVELS=smoke rel 0.9.0 gates regression; rc=$?
eq  "release gate: a backend:mps regression fails it" 1 "$rc"
has "release gate: holds the driver lock through the regression run" "run-release" "$(cat "$T/lock-seen")"
has "release gate: run-regression.sh runs under it, not waiting" "run-regression runs under" "$(cat "$T/h/logs/loop.log")"
eq  "release gate: and releases it at the end" "" "$(ls -d "$T/h/logs/.driver.lock" 2>/dev/null)"
has "release gate: and is listed" "S-F034 fails on mps" "$(jq -r '.["o/r"][] | select(.number == 51) | .comments[].body' "$T/board.json")"
rel 0.9.0 accept regression "suite drift only"
has "release: accept records Don's decision" "harnest:release-gate regression $sha accepted" "$(jq -r '.["o/r"][] | select(.number == 51) | .comments[].body' "$T/board.json")"
touch "$T/h/logs/stop-after-cycle.local"
rel 0.9.0 status
rm -f "$T/h/logs/stop-after-cycle.local"
has "release: status shows the accepted gate" "regression  accepted" "$(cat "$T/rel.out")"
has "release: and a leftover stop flag" "stop flags: stop-after-cycle.local" "$(cat "$T/rel.out")"
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

# --- 3f. the curator waits out a release freeze: a suite edit mid-freeze
# changes what the regression gate tests
: > "$FAKE_CLAUDE_LOG"
printf '%s\n' '{"o/r": [{"number": 60, "state": "OPEN", "title": "Release 0.9.0", "labels": [{"name": "release"}, {"name": "owner:don"}]}],
  "h/r": [{"number": 7, "state": "OPEN", "labels": [{"name": "suite"}, {"name": "status:needs-approval"}]}]}' > "$T/board.json"
loop 1
eq  "curator: held during a freeze" 0 "$(grep -c 'suite-change request #7' "$FAKE_CLAUDE_LOG")"
has "curator: and says why" "[curator] held: release freeze #60" "$(cat "$T/loop.out")"
jq '.["o/r"][0].state = "CLOSED"' "$T/board.json" > "$T/b2" && mv "$T/b2" "$T/board.json"
loop 1
eq  "curator: runs once the freeze lifts" 1 "$(grep -c 'suite-change request #7' "$FAKE_CLAUDE_LOG")"

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

# --- 6c. dw's stabilization freeze (FREEZE on origin/develop): no design, no
# build; the feature with a ready stage parks with Don; lifting it is dw's
dev_file() { # dev_file add|rm <path>: a commit on origin/develop
  git -C "$T/seed" pull -q origin develop 2>/dev/null; mkdir -p "$T/seed/$(dirname "$2")"
  if [ "$1" = add ]; then echo frozen > "$T/seed/$2"; git -C "$T/seed" add "$2"; else git -C "$T/seed" rm -q "$2"; fi
  git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm "$1 $2"; git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
}
dev_file add docs/stabilization/FREEZE
: > "$FAKE_CLAUDE_LOG"
specced='"comments": [{"author": {"login": "dkackman"}, "body": "<!-- harnest:plan v1 -->\nplan"}, {"author": {"login": "dkackman"}, "body": "<!-- harnest:decomposed v1 -->"}, {"author": {"login": "dkackman"}, "body": "<!-- harnest:specced v1 -->"}]'
board "[{\"number\": 22, \"state\": \"OPEN\", \"labels\": [{\"name\": \"idea\"}, {\"name\": \"owner:lead\"}]},
        {\"number\": 10, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"owner:lead\"}, {\"name\": \"status:plan-approved\"}], $specced, \"subIssuesSummary\": {\"total\": 1, \"completed\": 0}},
        {\"number\": 11, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"stage\"}, {\"name\": \"owner:lead\"}], \"parent\": {\"number\": 10}}]"
loop 1
eq  "freeze: no design session" 0 "$(grep -c 'DESIGN session' "$FAKE_CLAUDE_LOG")"
eq  "freeze: no build session" 0 "$(grep -c 'BUILD session' "$FAKE_CLAUDE_LOG")"
has "freeze: features_pass says why" "[features] skipping: dw stabilization freeze" "$(cat "$T/loop.out")"
has "freeze: lead_pass says why" "[lead] skipping builds: dw stabilization freeze" "$(cat "$T/loop.out")"
eq  "freeze: the feature parks with Don" "feature,owner:don,stabilization,status:plan-approved" "$(labels_of 10)"
eq  "freeze: its stage waits" "feature,owner:lead,stage" "$(labels_of 11)"
# The parks' label history (the fake records none), and two more parks:
# #40 by the hot-zone rule, which outlives the freeze; #41 with no history.
ev='[{"event": "unlabeled", "label": {"name": "owner:OWNER"}, "created_at": "2026-09-29T10:00:00Z"},
     {"event": "labeled", "label": {"name": "owner:don"}, "created_at": "2026-09-29T10:00:00Z"},
     {"event": "labeled", "label": {"name": "stabilization"}, "created_at": "2026-09-29T10:00:00Z"}]'
jq --argjson e10 "${ev//OWNER/lead}" --argjson e40 "${ev//OWNER/implementer}" '.["o/r"] |= map(if .number == 10 then .events = $e10 else . end)
  | .["o/r"] += [{"number": 40, "state": "OPEN", "labels": [{"name": "owner:don"}, {"name": "stabilization"}], "events": $e40,
                  "comments": [{"author": {"login": "dkackman"}, "createdAt": "2026-09-29T10:01:00Z", "body": "Parked: guard refused, rule hot-zone on dw/realize.py"}]},
                 {"number": 41, "state": "OPEN", "labels": [{"name": "owner:don"}, {"name": "stabilization"}]}]' "$T/board.json" > "$T/b2" && mv "$T/b2" "$T/board.json"
dev_file rm docs/stabilization/FREEZE
: > "$FAKE_CLAUDE_LOG"
loop 1
eq  "freeze lifted: the idea is designed" 1 "$(grep -c 'DESIGN session for issue #22' "$FAKE_CLAUDE_LOG")"
eq  "unpark: the parked feature has its owner back" "feature,owner:lead,status:plan-approved,target:lem" "$(labels_of 10)"
eq  "unpark: and its build resumes" 1 "$(grep -c 'BUILD session for stage #11' "$FAKE_CLAUDE_LOG")"
eq  "unpark: a hot-zone park stays with Don" "owner:don,stabilization" "$(labels_of 40)"
has "  with a one-line comment saying why" "Left with Don after dw's stabilization freeze lifted: it was parked by the hot-zone rule" "$(jq -r '.["o/r"][] | select(.number == 40) | .comments[-1].body' "$T/board.json")"
has "  as does one with no owner in its history" "no owner from before the park" "$(jq -r '.["o/r"][] | select(.number == 41) | .comments[-1].body' "$T/board.json")"
has "unpark: the log lists what it touched" "[lead:unpark] freeze lifted; stabilization issues: #10->owner:lead #40:left" "$(cat "$T/loop.out")"
loop 1
eq  "unpark: once per lift" 0 "$(grep -c '\[lead:unpark\]' "$T/loop.out")"
# a stage parked after four bounces that Don hands back gets a build, not
# another park (#499 was re-parked twice with no session in between)
fpv='{"event": "labeled", "label": {"name": "status:fixed-pending-verify"}}'
board "[{\"number\": 10, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"owner:lead\"}, {\"name\": \"status:plan-approved\"}], $specced, \"subIssuesSummary\": {\"total\": 1, \"completed\": 0}},
        {\"number\": 11, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"stage\"}, {\"name\": \"owner:lead\"}], \"parent\": {\"number\": 10},
         \"events\": [$fpv, $fpv, $fpv, $fpv, {\"event\": \"labeled\", \"label\": {\"name\": \"owner:don\"}}, {\"event\": \"unlabeled\", \"label\": {\"name\": \"owner:don\"}}]}]"
: > "$FAKE_CLAUDE_LOG"
loop 1
eq  "hand-back: the four-bounce stage is built" 1 "$(grep -c 'BUILD session for stage #11' "$FAKE_CLAUDE_LOG")"
eq  "  and not re-parked" "" "$(grep 'stage bounced' "$T/loop.out" || true)"
jq '(.["o/r"][] | select(.number == 11) | .events) |= .[0:4]' "$T/board.json" > "$T/b2" && mv "$T/b2" "$T/board.json"
jq '(.["o/r"][] | select(.number == 11) | .labels) = [{"name": "feature"}, {"name": "stage"}, {"name": "owner:lead"}]' "$T/board.json" > "$T/b2" && mv "$T/b2" "$T/board.json"
: > "$FAKE_CLAUDE_LOG"
loop 1
eq  "without a hand-back, four bounces still park" "stage bounced 4 times; parking with owner:don" "$(grep -o 'stage bounced 4 times; parking with owner:don' "$T/loop.out")"

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

# --- 7b. run-regression against the mini-ai test bed (harnest#15), with
# the loop's lock held: it must not wait on lem's. ssh: lem reports its
# commit; mini-ai reports $T/mini-head, and a deploy there is logged to
# $T/deploys, exits $T/deploy-rc (0 when absent), and on success moves
# mini-ai to origin/develop and brings its server up ($T/up).
printf '%s\n' "${sha:0:9}" > "$T/lem-head"
cat > "$T/bin/ssh" <<EOS
#!/usr/bin/env bash
echo "ssh \$*" >> "$T/ssh-calls"
case "\$*" in
  *mini-ai*deploy.sh*) echo "deploy develop" >> "$T/deploys"; rc=\$(cat "$T/deploy-rc" 2>/dev/null || echo 0)
                       [ "\$rc" != 0 ] || { git -C "$T/src" rev-parse --short=9 origin/develop > "$T/mini-head"; touch "$T/up"; }
                       echo "[deploy] done"; exit "\$rc" ;;
  *mini-ai*) echo "develop @ \$(cat "$T/mini-head" 2>/dev/null || echo 0000000)" ;;
  *) echo "develop @ \$(cat "$T/lem-head")" ;;
esac
EOS
chmod +x "$T/bin/ssh"
mini_health() { printf '#!/usr/bin/env bash\n%secho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "${2:-}" "${1:-mini-ai.lan}" > "$T/bin/curl"; chmod +x "$T/bin/curl"; }
: > "$FAKE_CLAUDE_LOG"
mini_health
mkdir "$T/h/logs/.driver.lock"; echo "$$ run-loop" > "$T/h/logs/.driver.lock/owner"
reg_mini() {
  (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
     PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 SESSION_RETRY_PAUSE_SECS=0 \
     FAKE_CLAUDE_DO='printf "%s" "$2" > "$FAKE_PROMPT"; printf "%s\n" "$@" > "$FAKE_PROMPT.args"; echo "${HARNEST_TARGET:-unset}" > "$FAKE_PROMPT.target"' FAKE_PROMPT="$T/mini-prompt" \
     ./run-regression.sh smoke regression-suite-tiny.md) > "$T/reg-mini.out" 2>&1
}
echo "dirty" >> "$T/h/regression-suite-tiny.md"   # a lem-side edit in progress
printf '%s\n' "${sha:0:7}" > "$T/mini-head"
before_head="$(git -C "$T/h" rev-parse HEAD)"
reg_mini
eq  "regression mini-ai: runs while lem's lock is held" 0 $?
eq  "regression mini-ai: one whole-level session" 1 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "regression mini-ai: header names the target and its checkout" "target=mini-ai, head=develop @ ${sha:0:7}" "$(grep 'regression run (' "$T/h/logs/loop.mini-ai.log" | tail -1)"
sysprompt="$(cat "$T/h/logs/.prompt.regression.mini-ai.whole.md")"
has "regression mini-ai: prompt names the server it asked" "the mini-ai server (mps on mini-ai.lan) is running develop @ " "$(cat "$T/mini-prompt")"
has "regression mini-ai: system prompt moves perf history" "regression-perf/mini-ai/<case>.jsonl" "$sysprompt"
has "regression mini-ai: system prompt files for the implementer with a backend" "\`owner:implementer\` and \`backend:mps\`" "$sysprompt"
has "regression mini-ai: system prompt forbids suite edits" "The suite files. Every case in them runs on lem" "$sysprompt"
eq  "regression mini-ai: the guard is told the target" "mini-ai" "$(cat "$T/mini-prompt.target")"
has "regression mini-ai: skip and differ counts are logged" "case(s) skipped" "$(cat "$T/reg-mini.out")"
eq  "regression mini-ai: no suite commit" "$before_head" "$(git -C "$T/h" rev-parse HEAD)"
has "regression mini-ai: header tags the level for the curator" "level=smoke.mini-ai," "$(grep 'regression run (' "$T/h/logs/loop.mini-ai.log" | tail -1)"
has "regression mini-ai: sessions are labelled for retro" "[regression-mini-ai:smoke] usage:" "$(cat "$T/reg-mini.out")"
# what the test bed deploys is origin/develop, so its plugin is its own worktree there
has "regression mini-ai: plugin is its own worktree's" "--plugin-dir
$T/plugin-mini/plugins/dw" "$(cat "$T/mini-prompt.args")"
eq  "  at origin/develop" "$(git -C "$T/src" rev-parse origin/develop)" "$(git -C "$T/plugin-mini" rev-parse HEAD)"
ok  "regression mini-ai: its own log" test -s "$T/h/logs/regression.mini-ai.log"
eq  "regression mini-ai: the lem lock is left as it was" "$$ run-loop" "$(cat "$T/h/logs/.driver.lock/owner")"
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
   PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=1 SESSION_RETRY_PAUSE_SECS=0 \
   ./run-regression.sh smoke regression-suite-tinymem.md) > "$T/reg-mem.out" 2>&1
eq  "regression mini-ai: held-back case runs no session (one chunk + sweep)" 2 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "regression mini-ai: the held-back case is logged as skipped" "REGRESSION-SKIP: S-F079 memory" "$(cat "$T/reg-mem.out")"
has "regression mini-ai: and counted" "1 case(s) skipped" "$(cat "$T/reg-mem.out")"
eq  "regression mini-ai: only S-F001 is handed out" "" "$(grep 'session .*: .*S-F079' "$T/h/logs/loop.mini-ai.log" || true)"
rm -rf "$T/h/logs/.driver.lock"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
: > "$FAKE_CLAUDE_LOG"
reg_mini
eq  "regression mini-ai: no server answering stops it" 1 $?
has "regression mini-ai: and says so, and how to start it" "no dw server answering at http://mini-ai:8765/mcp (DW_TARGET=mini-ai): scripts/testbed.sh mini-ai start" "$(cat "$T/reg-mini.out")"
eq  "regression mini-ai: before any session" 0 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
mini_health lem
reg_mini
eq  "regression mini-ai: another host answering stops it" 1 $?
has "  and says which" "is lem, not mini-ai" "$(cat "$T/reg-mini.out")"
rm -f "$T/bin/curl"
(cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin" DW_TARGET=local MAX_CYCLES=1 ./run-loop.sh) > "$T/loop-local.out" 2>&1
eq  "loop: the retired local target is refused" 1 $?
has "  naming the targets there are" "must be one of: lem mini-ai" "$(cat "$T/loop-local.out")"

# --- 10. the loop on the mini-ai test bed (harnest#15 part 2): its own lock,
# log and clones; it claims what it works, leaves lem's and cuda issues
# alone, and deploys develop there over ssh, as lem's loop does to lem
mini_health
mini_loop() {
  (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r TICKET_OWNER=dkackman \
     DW_TARGET=mini-ai SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin-mini" LEAD_TREE="$T/lead-mini" \
     MAX_CYCLES=1 SLEEP_SECS=0 SESSION_RETRY_PAUSE_SECS=0 "$@" ./run-loop.sh) > "$T/loop-mini.out" 2>&1
}
: > "$FAKE_CLAUDE_LOG"; : > "$T/deploys"; : > "$T/ssh-calls"
board '[{"number": 30, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:shared"}]},
        {"number": 31, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:cuda"}]},
        {"number": 32, "state": "OPEN", "labels": [{"name": "owner:tester"}, {"name": "status:fixed-pending-verify"}]},
        {"number": 33, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "target:lem"}]}]'
mkdir "$T/h/logs/.driver.lock"; echo "$$ run-loop" > "$T/h/logs/.driver.lock/owner"   # lem's loop, live
echo 0000000 > "$T/mini-head"   # mini-ai behind develop
mini_loop TESTER_TASK_EVERY=1 FAKE_CLAUDE_DO='printf "%s\n" "$@" > "$FAKE_PROMPT.args"; echo "${HARNEST_TARGET:-unset}/${HARNEST_ROLE:-unset}/${HARNEST_TARGET_HOST:-unset}" >> "$FAKE_PROMPT.env"' FAKE_PROMPT="$T/mini-loop"
eq  "mini-ai loop: runs beside lem's lock" 0 $?
eq  "mini-ai loop: claims the shared issue" "backend:shared,owner:implementer,target:mini-ai" "$(labels_of 30)"
eq  "mini-ai loop: leaves the cuda issue alone" "backend:cuda,owner:implementer" "$(labels_of 31)"
eq  "mini-ai loop: leaves lem's claim alone" "owner:implementer,target:lem" "$(labels_of 33)"
eq  "mini-ai loop: one session, the shared fix (lem's hand-off waits)" 1 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
has "mini-ai loop: the prompt names the test bed" "the mini-ai server (mps on mini-ai.lan) is running: " "$(cat "$T/mini-loop.args")"
has "mini-ai loop: the implementer's settings are the test bed's" "agent-settings/implementer.mini-ai.json" "$(cat "$T/mini-loop.args")"
has "mini-ai loop: deploy command in the system prompt" "ssh -o ConnectTimeout=8 -o BatchMode=yes mini-ai '~/diffusers-workflow/scripts/deploy.sh develop'" "$(cat "$T/h/logs/.prompt.implementer.mini-ai.fix.md")"
eq  "mini-ai loop: the guard is told the target and its host" "mini-ai/implementer/mini-ai" "$(head -1 "$T/mini-loop.env")"
ok  "mini-ai loop: its own log" test -s "$T/h/logs/loop.mini-ai.log"
ok  "mini-ai loop: its own implementer log" test -s "$T/h/logs/implementer.mini-ai.log"
has "mini-ai loop: shared passes stay with lem's loop" "skipping: lem's loop runs it" "$(cat "$T/h/logs/loop.mini-ai.log")"
has "mini-ai loop: no standing task" "standing task: lem only" "$(cat "$T/h/logs/loop.mini-ai.log")"
eq  "mini-ai loop: lem's lock untouched" "$$ run-loop" "$(cat "$T/h/logs/.driver.lock/owner")"
has "mini-ai loop: behind develop, it deploys develop" "deploy develop" "$(cat "$T/deploys")"
eq  "mini-ai loop: over ssh to mini-ai, never lem" "" "$(grep 'deploy.sh' "$T/ssh-calls" | grep -v ' mini-ai ' || true)"

# IMPLEMENTER_CLAIM_MAX: a pass claims at most N, oldest first; the rest stay unclaimed
board '[{"number": 40, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:shared"}]},
        {"number": 41, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:shared"}]},
        {"number": 42, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:shared"}]}]'
mini_loop IMPLEMENTER_CLAIM_MAX=2
eq  "claim cap: first claimed" "backend:shared,owner:implementer,target:mini-ai" "$(labels_of 40)"
eq  "claim cap: second claimed" "backend:shared,owner:implementer,target:mini-ai" "$(labels_of 41)"
eq  "claim cap: third left unclaimed" "backend:shared,owner:implementer" "$(labels_of 42)"
has "claim cap: logged" "claim cap reached (IMPLEMENTER_CLAIM_MAX=2)" "$(cat "$T/h/logs/loop.mini-ai.log")"

# a feature is claimed whole: the Mac builds the stage of an unclaimed feature
# (claiming parent and stage), and leaves a feature lem holds alone
specced='"comments": [{"author": {"login": "dkackman"}, "body": "<!-- harnest:plan v1 -->\nplan"}, {"author": {"login": "dkackman"}, "body": "<!-- harnest:decomposed v1 -->"}, {"author": {"login": "dkackman"}, "body": "<!-- harnest:specced v1 -->"}]'
: > "$FAKE_CLAUDE_LOG"
board "[{\"number\": 50, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"owner:lead\"}, {\"name\": \"status:plan-approved\"}], $specced, \"subIssuesSummary\": {\"total\": 1, \"completed\": 0}},
        {\"number\": 51, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"stage\"}, {\"name\": \"owner:lead\"}], \"parent\": {\"number\": 50}},
        {\"number\": 52, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"owner:lead\"}, {\"name\": \"status:plan-approved\"}, {\"name\": \"target:lem\"}], $specced, \"subIssuesSummary\": {\"total\": 1, \"completed\": 0}},
        {\"number\": 53, \"state\": \"OPEN\", \"labels\": [{\"name\": \"feature\"}, {\"name\": \"stage\"}, {\"name\": \"owner:lead\"}], \"parent\": {\"number\": 52}}]"
mini_loop
eq  "feature claim: the parent is claimed" "feature,owner:lead,status:plan-approved,target:mini-ai" "$(labels_of 50)"
eq  "feature claim: so is the stage" "feature,owner:lead,stage,target:mini-ai" "$(labels_of 51)"
eq  "feature claim: lem's feature is left alone" "feature,owner:lead,stage" "$(labels_of 53)"
eq  "feature claim: one build session, the unclaimed feature's" 1 "$(grep -c 'BUILD session' "$FAKE_CLAUDE_LOG")"
eq  "mini-ai loop: and the test bed is on develop after" "$(git -C "$T/src" rev-parse --short=9 origin/develop)" "$(cat "$T/mini-head")"
rm -rf "$T/h/logs/.driver.lock"
# tie: lem's claim lands in the same moment; the Mac yields
board '[{"number": 40, "state": "OPEN", "labels": [{"name": "owner:implementer"}, {"name": "backend:shared"}]}]'
: > "$FAKE_CLAUDE_LOG"
mini_loop FAKE_GH_ON_EDIT_40=target:lem
eq  "tie: no session on the Mac" 0 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"
eq  "tie: lem keeps it" "backend:shared,owner:implementer,target:lem" "$(labels_of 40)"
# behind develop again: the driver deploys develop there, and the claimed hand-off is verified
: > "$T/deploys"; echo 0000000 > "$T/mini-head"
board '[{"number": 41, "state": "OPEN", "labels": [{"name": "owner:tester"}, {"name": "status:fixed-pending-verify"}, {"name": "target:mini-ai"}]}]'
: > "$FAKE_CLAUDE_LOG"
mini_loop
has "deploy: the develop check deploys to the test bed" "deploy develop" "$(cat "$T/deploys")"
eq  "deploy: the claimed hand-off is verified here" 1 "$(grep -c 'VERIFY session' "$FAKE_CLAUDE_LOG")"
# a failed deploy is logged, and the tester still runs
echo 1 > "$T/deploy-rc"
: > "$FAKE_CLAUDE_LOG"; echo 0000000 > "$T/mini-head"
mini_loop
has "deploy fails: logged" "driver deploy of develop failed" "$(cat "$T/h/logs/loop.mini-ai.log")"
eq  "deploy fails: the tester still verifies" 1 "$(grep -c 'VERIFY session' "$FAKE_CLAUDE_LOG")"
rm -f "$T/deploy-rc"
# no server answering (the test bed left stopped): the loop deploys develop there, then checks it
rm -f "$T/up"; echo 0000000 > "$T/mini-head"
mini_health mini-ai.lan "[ -e '$T/up' ] || exit 7; "
board '[]'
mini_loop
eq  "bootstrap: the loop starts with the test bed stopped" 0 $?
has "bootstrap: by deploying develop to it" "no server answering at http://mini-ai:8765/mcp; deploying develop to mini-ai" "$(cat "$T/h/logs/loop.mini-ai.log")"
mini_health
# closures: the Mac tester answers only closures it holds; lem's skip them
board '[{"number": 60, "state": "CLOSED", "labels": [{"name": "owner:tester"}, {"name": "wontfix"}, {"name": "target:mini-ai"}]},
        {"number": 61, "state": "CLOSED", "labels": [{"name": "owner:tester"}, {"name": "wontfix"}]}]'
: > "$FAKE_CLAUDE_LOG"
: > "$T/prompts"
mini_loop FAKE_CLAUDE_DO='printf "%s\n" "$2" >> "'"$T"'/prompts"'
has "closures: the Mac takes its own" "CLOSURES session for #60 only" "$(cat "$T/prompts")"
eq  "closures: not lem's" "" "$(grep 'CLOSURES session' "$T/prompts" | grep '#61' || true)"
: > "$T/prompts"
FAKE_CLAUDE_DO='printf "%s\n" "$2" >> "'"$T"'/prompts"' loop 1
has "closures: lem takes its own" "CLOSURES session for #61 only" "$(cat "$T/prompts")"
# a mini-ai regression run waits on the mini-ai loop's lock, not lem's
mkdir "$T/h/logs/.driver.lock.mini-ai"; echo "$$ run-loop" > "$T/h/logs/.driver.lock.mini-ai/owner"
(cd "$T/h" && exec env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
   PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 ./run-regression.sh smoke regression-suite-tiny.md) > "$T/reg-wait.out" 2>&1 &
regpid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q waiting "$T/reg-wait.out" 2>/dev/null && break; sleep 1; done
kill "$regpid" 2>/dev/null; wait "$regpid" 2>/dev/null
has "regression waits on the mini-ai loop" "waiting for '$$ run-loop'" "$(cat "$T/reg-wait.out")"
rm -rf "$T/h/logs/.driver.lock.mini-ai"; rm -f "$T/bin/curl"

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
# --- 9b. the nightly regression run: once a day, inside the loop, under its lock
: > "$FAKE_CLAUDE_LOG"; rm -f "$T/h/logs/.nightly-regression"
board '[]'
REGRESSION_NIGHTLY_AT=0 REGRESSION_NIGHTLY_LEVEL="smoke regression-suite-tiny.md" loop 1
has "nightly: runs at the cycle boundary" "[nightly] run-regression.sh smoke regression-suite-tiny.md" "$(cat "$T/loop.out")"
has "nightly: under the loop's lock, not waiting on it" "run-regression runs under" "$(cat "$T/h/logs/loop.log")"
has "nightly: the level ran, logged apart" "regression run (" "$(cat "$T/h/logs/nightly-regression.log")"
REGRESSION_NIGHTLY_AT=0 REGRESSION_NIGHTLY_LEVEL="smoke regression-suite-tiny.md" loop 1
eq  "nightly: once a day" 1 "$(grep -c '\[nightly\] run-regression' "$T/h/logs/loop.log")"
loop 1
eq  "nightly: off unless asked" 1 "$(grep -c '\[nightly\] run-regression' "$T/h/logs/loop.log")"

# --- 10. run-release.sh across a moving develop: a waiver holds check, and
# gates carry across the notes and a verified blocker's fix (last: it moves
# develop, which every section above reads)
board '[{"number": 70, "state": "OPEN", "title": "Release 0.9.1", "labels": [{"name": "release"}, {"name": "owner:don"}]},
        {"number": 71, "state": "OPEN", "labels": [{"name": "owner:don"}, {"name": "feature"}]},
        {"number": 72, "state": "CLOSED", "labels": [{"name": "release-blocker"}, {"name": "status:verified"}]}]'
commit_dev() { # commit_dev <file> <subject>: a commit on origin/develop
  git -C "$T/seed" pull -q origin develop 2>/dev/null; mkdir -p "$T/seed/$(dirname "$1")"
  echo "$2" >> "$T/seed/$1"; git -C "$T/seed" add -A
  git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm "$2"; git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
  git -C "$T/src" fetch -q origin; git -C "$T/src" rev-parse origin/develop
}
s0="$(commit_dev dw/a.py "feat(tasks): #71 - stage one")"
printf '#!/usr/bin/env bash\necho "develop @ %s"\n' "${s0:0:9}" > "$T/bin/ssh"
rel 0.9.1 check; rc=$?
eq  "waive: an open issue with commits on develop fails check" 1 "$rc"
rel 0.9.1 accept check --waive 71 "stage one ships alone"
has "waive: recorded as a marker" "harnest:release-waive 71" "$(jq -r '.["o/r"][] | select(.number == 70) | .comments[].body' "$T/board.json")"
rel 0.9.1 accept review "reviewed"; rel 0.9.1 accept security "reviewed"; rel 0.9.1 accept regression "ran"
s1="$(commit_dev dw/b.py "fix(mcp): #72 - the blocker")"
s2="$(commit_dev docs/RELEASING.md "docs(release): 0.9.1 notes")"
printf '#!/usr/bin/env bash\necho "develop @ %s"\n' "${s2:0:9}" > "$T/bin/ssh"
rel 0.9.1 check; rc=$?
eq  "waive: the next commit's check passes by itself" 0 "$rc"
has "waive: and says what it waived" "Waived: #71" "$(jq -r '.["o/r"][] | select(.number == 70) | .comments[].body' "$T/board.json")"
rel 0.9.1 status
has "carry: review carried across the blocker fix and the notes" "review      carried" "$(cat "$T/rel.out")"
has "carry: security too" "security    carried" "$(cat "$T/rel.out")"
has "carry: regression is not, across a code fix" "regression: not carried from ${s0:0:10}" "$(cat "$T/rel.out")"
has "carry: the marker lists the commits" "- ${s1:0:10} fix(mcp): #72 - the blocker" "$(jq -r '.["o/r"][] | select(.number == 70) | .comments[].body' "$T/board.json")"
rel 0.9.1 accept regression "blocker verified"
s3="$(commit_dev docs/RELEASING.md "docs(release): notes typo")"
printf '#!/usr/bin/env bash\necho "develop @ %s"\n' "${s3:0:9}" > "$T/bin/ssh"
rel 0.9.1 status
has "carry: regression carries across the notes alone" "regression  carried" "$(cat "$T/rel.out")"
has "waive: status lists waivers" "waived      #71" "$(cat "$T/rel.out")"
# the regression gate: suite drift goes to the harness repo and doesn't count
FAKE_CLAUDE_DO='gh issue list --repo h/r --label suite --json number --jq length | grep -q "^0$" && gh issue create --repo h/r --title "suite: C-F037 - the template plans 8 steps" --label suite --label status:needs-approval >/dev/null; true' \
  RELEASE_FORCE=1 RELEASE_REGRESSION_LEVELS=smoke rel 0.9.1 gates regression; rc=$?
FAKE_CLAUDE_DO=''
eq  "drift: a suite request alone passes the gate" 0 "$rc"
has "drift: and is listed, not counted" "h/r#1 suite: C-F037 - the template plans 8 steps" "$(jq -r '.["o/r"][] | select(.number == 70) | .comments[].body' "$T/board.json")"

for f in loop features reg curate retro; do cp "$T/$f.out" "/tmp/claude-501/last-$f.out" 2>/dev/null; done
finish
