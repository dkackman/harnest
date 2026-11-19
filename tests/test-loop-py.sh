#!/usr/bin/env bash
# The Python loop driver (harness/drivers/loop.py, R17) end to end, offline,
# in the style of test-regression-py.sh: a throwaway git origin with a develop
# branch, clones for SOURCE_DIR, a copy of this harness as its own repo, and
# fakes for gh (tests/fake-gh.py over a JSON board), ssh (deployed heads and
# deploy.sh, recorded), curl (/api/health) and claude (sleeps, and logs when
# each session starts and ends). Every run is bounded: --once, MAX_SESSIONS or
# a signal. Each scenario runs in its own world ($T/<name>, a subshell in the
# background), so the file takes about as long as its longest scenario.
. "$(dirname "$0")/lib.sh"

# --- the harness copy every world clones (main is its suite branch)
mkdir "$T/h0"
(cd "$HARNEST" && tar cf - --exclude ./logs --exclude ./.git --exclude ./.env --exclude ./.superpowers .) | (cd "$T/h0" && tar xf -)
rm -f "$T/h0"/regression-results/*.jsonl "$T/h0"/regression-results/*/*.jsonl
git -C "$T/h0" init -q -b main && git -C "$T/h0" add -A && git -C "$T/h0" -c user.name=t -c user.email=t@t commit -qm h
ln -s "$HARNEST/tests/fake-gh.py" "$T/bin/gh"

# world: a fresh world under $T (a scenario's own: the caller set T)
world() {
  mkdir -p "$T/bin" "$T/logs"; export PATH="$T/bin:$PATH" FAKE_CLAUDE_LOG="$T/claude-calls" FAKE_GH_LOG="$T/gh-calls"
  : > "$FAKE_CLAUDE_LOG"; : > "$FAKE_CLAUDE_LOG.argv"; : > "$T/deploys"; : > "$T/gh-calls"
  git init -q --bare "$T/origin.git"
  git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
  mkdir -p "$T/seed/plugins/dw" "$T/seed/dw"; echo x > "$T/seed/plugins/dw/README"; echo x > "$T/seed/dw/core.py"
  git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm seed
  git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
  git clone -q -b develop "$T/origin.git" "$T/src"
  git clone -q -b develop "$T/origin.git" "$T/src-mini-ai"
  git -C "$T/src" rev-parse --short HEAD > "$T/lem-head"
  git -C "$T/src" rev-parse --short HEAD > "$T/mini-ai-head"
  git clone -q --no-local -b main "$T/../h0" "$T/h" 2>/dev/null   # --no-local: parallel local clones race on loose objects
  mkdir -p "$T/h/logs"
  # ssh: the deployed head is $T/<server>-head; deploy.sh is recorded (with
  # the time) and moves it to develop, or fails while $T/deploy-fails exists
  # ($T/deploy-moves-fails: moves it, takes /api/health down, then fails;
  # $T/deploy-false-fails: moves it, health stays up, and fails anyway;
  # $T/deploy-sleep: takes that many seconds first; a success records its end)
  cat > "$T/bin/ssh" <<EOS
#!/usr/bin/env bash
srv=lem; case "\$*" in *mini-ai*) srv=mini-ai ;; esac
case "\$*" in
  *deploy.sh*)
    echo "\$(python3 -c 'import time; print(time.time())') \$srv deploy.sh" >> "$T/deploys"
    [ ! -e "$T/deploy-sleep" ] || sleep "\$(cat "$T/deploy-sleep")"
    [ ! -e "$T/deploy-fails" ] || { echo "deploy: health check timed out"; exit 1; }
    git -C "$T/src" fetch -q origin develop; git -C "$T/src" rev-parse --short origin/develop > "$T/\$srv-head"
    [ ! -e "$T/deploy-moves-fails" ] || { touch "$T/health-down"; echo "deploy: health check timed out"; exit 1; }
    [ ! -e "$T/deploy-false-fails" ] || { echo "dw.serve exited during startup"; exit 1; }
    echo "\$(python3 -c 'import time; print(time.time())') \$srv deploy.sh ended" >> "$T/deploy-ends"
    echo "deployed develop" ;;
  *) echo "develop @ \$(cat "$T/\$srv-head" 2>/dev/null || echo 0000000)" ;;
esac
EOS
  # curl: /api/health names the server the URL is on; lem has two idle
  # workers, and doesn't answer while $T/health-down exists
  cat > "$T/bin/curl" <<EOS
#!/usr/bin/env bash
case "\$*" in *mini-ai*) ;; *) [ ! -e "$T/health-down" ] || exit 7 ;; esac
case "\$*" in
  *mini-ai*) echo '{"status":"ok","device":"mps","hostname":"mini-ai.lan","workers":[{"device":"mps","current_job":null}]}' ;;
  *) echo '{"status":"ok","device":"cuda","hostname":"lem","workers":[{"device":"cuda:0","current_job":null},{"device":"cuda:1","current_job":null}]}' ;;
esac
EOS
  # claude: logs "start|end <epoch> <kind> <cwd> <target>" around
  # FAKE_CLAUDE_SLEEP seconds (FAKE_CLAUDE_SLEEP_<kind> for one kind;
  # FAKE_CLAUDE_FIRST runs before it), then runs
  # FAKE_CLAUDE_DO (an agent's action) and reports a $0.25 result.
  # FAKE_CLAUDE_REJECT (a marker file): the first session is turned away by a
  # rate limit that resets FAKE_CLAUDE_REJECT_IN seconds after the minute the
  # item waits past it, and writes the time into the marker
  cat > "$T/bin/claude" <<'EOS'
#!/usr/bin/env bash
kind=other
case "$*" in
  *"VERIFY session"*) kind=verify ;; *"ANSWER session"*) kind=answer ;; *"SPEC session"*) kind=spec ;;
  *"TASK session"*) kind=task ;; *"CLOSURES session"*) kind=closures ;; *"fix session"*) kind=fix ;;
  *"TRIAGE session"*) kind=triage ;; *"DESIGN session"*) kind=design ;; *"DOCS REVIEW"*) kind=docs ;;
esac
now() { python3 -c 'import time; print(time.time())'; }
echo "start $(now) $kind $PWD ${HARNEST_TARGET:-${DW_TARGET:-}}" >> "$FAKE_CLAUDE_LOG"
echo "claude $*" >> "$FAKE_CLAUDE_LOG.argv"
echo '{"type":"system","subtype":"init","model":"claude-fake"}'
if [ -n "${FAKE_CLAUDE_REJECT:-}" ] && [ ! -e "$FAKE_CLAUDE_REJECT" ]; then
  now > "$FAKE_CLAUDE_REJECT"
  echo "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"rejected\",\"rateLimitType\":\"five_hour\",\"isUsingOverage\":false,\"resetsAt\":$(( $(date +%s) + ${FAKE_CLAUDE_REJECT_IN:-0} - 60 ))}}"
  # what changes on the board meanwhile (after the driver has seen the line)
  [ -z "${FAKE_CLAUDE_ON_REJECT:-}" ] || { sleep 0.5; eval "$FAKE_CLAUDE_ON_REJECT" >/dev/null 2>&1; }
  echo '{"type":"result","subtype":"success","num_turns":1,"duration_ms":10,"total_cost_usd":0,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}'
  exit 0
fi
[ -z "${FAKE_CLAUDE_FIRST:-}" ] || eval "$FAKE_CLAUDE_FIRST" >/dev/null 2>&1
eval "sl=\${FAKE_CLAUDE_SLEEP_$kind:-\${FAKE_CLAUDE_SLEEP:-0}}"
sleep "$sl"
[ -z "${FAKE_CLAUDE_DO:-}" ] || eval "$FAKE_CLAUDE_DO" >/dev/null 2>&1
echo "end $(now) $kind $PWD" >> "$FAKE_CLAUDE_LOG"
echo '{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.25,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}'
EOS
  chmod +x "$T/bin/ssh" "$T/bin/curl" "$T/bin/claude"
}

# commit <file> <message>: a merge to develop, as a hand-off makes; prints its sha
commit() {
  git -C "$T/seed" pull -q origin develop 2>/dev/null
  echo "$RANDOM" >> "$T/seed/$1"
  git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm "$2"
  git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
  git -C "$T/seed" rev-parse --short HEAD
}
deployed_is_develop() { git -C "$T/src" fetch -q origin develop; git -C "$T/src" rev-parse --short origin/develop > "$T/lem-head"; }
board() { printf '{"o/r": %s, "h/r": %s}\n' "$1" "${2:-[]}" > "$T/board.json"; }
labels_of() { jq -r --arg n "$1" '.["o/r"][] | select((.number|tostring) == $n) | [.labels[].name] | sort | join(",")' "$T/board.json"; }
issue() { # issue <n> <label>...: an open issue as the fake board holds it
  local n="$1" l out=""; shift
  for l in "$@"; do out="$out${out:+, }{\"name\": \"$l\"}"; done
  printf '{"number": %s, "state": "OPEN", "title": "issue %s", "labels": [%s]}' "$n" "$n" "$out"
}
# drv_start [VAR=value ...] -- <driver args>: the real driver over the world,
# in the background ($drv is its pid), output in $T/loop.out; --servers lem
# unless the args name servers. It polls every 5 s (a session's end wakes it
# at once); a scenario whose board changes mid-session polls faster
drv_start() {
  local -a vars=()
  while [ "$1" != -- ]; do vars+=("$1"); shift; done; shift
  case " $* " in *" --servers "*) ;; *) set -- --servers lem "$@" ;; esac
  (cd "$T/h" && exec env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r TICKET_OWNER=dkackman \
     SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin" LEAD_TREE="$T/lead" SESSION_RETRY_PAUSE_SECS=0 \
     LOOP_POLL_SECS=5 LOOP_HEALTH_SECS=2 TESTER_TASK_GAP_SECS=999999 \
     ${vars[@]+"${vars[@]}"} python3 -m harness.drivers.loop "$@") > "$T/loop.out" 2>&1 &
  drv=$!
}
# drv_wait [secs]: wait for it (default 40 s), killing it past that
drv_wait() {
  local i
  for i in $(seq 1 $(( ${1:-40} * 10 ))); do kill -0 "$drv" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$drv" 2>/dev/null; then kill -KILL "$drv"; echo "driver timed out" >> "$T/loop.out"; fi
  wait "$drv"
}
run() { drv_start "$@"; drv_wait; }
# until_ <secs> <command...>: poll for a condition, 50 ms apart
until_() { local n=$(( $1 * 20 )); shift; while [ "$n" -gt 0 ]; do "$@" >/dev/null 2>&1 && return 0; sleep 0.05; n=$((n - 1)); done; return 1; }
started() { [ "$(grep -c '^start' "$FAKE_CLAUDE_LOG")" -ge "$1" ]; }
# starts <kind> / ends <kind>: the times that kind's sessions started / ended
starts() { awk -v k="$1" '$1 == "start" && $3 == k { print $2 }' "$FAKE_CLAUDE_LOG"; }
ends() { awk -v k="$1" '$1 == "end" && $3 == k { print $2 }' "$FAKE_CLAUDE_LOG"; }
lt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }
ge_by() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) >= float(sys.argv[3]) else 1)' "$1" "$2" "$3"; }
state() { jq -r "$1" "$T/h/logs/loop/state.json"; }
deploy_state() { [ "$(jq -r '"\(.servers.lem.deploy.state) \(.servers.lem.deploy.waiting | join(" "))"' "$T/h/logs/loop/state.json" 2>/dev/null)" = "$1" ]; }
snap_state() { cp "$T/h/logs/loop/state.json" "$T/$1" 2>/dev/null; }

# The issue number a fake session was started for, from its prompt; and what
# the fake agents do with it.
n_of='n="$(printf "%s" "$*" | grep -oE "(issue|feature) #[0-9]+" | head -1 | grep -oE "[0-9]+")"'
close_it="$n_of"'; gh issue close "$n" --repo o/r --reason completed'
add_case="$n_of"'; echo "### S-F9$n — a case the verify of #$n added" >> regression-suite-smoke.md'
plan_to_don="$n_of"'; gh issue edit "$n" --repo o/r --remove-label owner:lead --add-label owner:don --add-label status:needs-approval'

# scenario <name> <function>: run it in its own world, in the background
scenario() {
  ( T="$T/$1"; mkdir -p "$T"; t0=$SECONDS; world; "$2"; echo "  ($1: $((SECONDS - t0))s)" >&2
    [ "$_fail" = 0 ] || { echo "  --- $1: the last driver run's output"; tail -15 "$T/loop.out" 2>/dev/null | sed 's/^/  | /'; }
    echo "$_pass $_fail" > "$T/tally" ) > "$T/$1.out" 2>&1 &
  scenarios="${scenarios:-} $1"
}

# --- lib/board.sh: classify rows with the claim holder, and the queries
s_board() {
  board "[$(issue 1 owner:implementer), $(issue 2 owner:tester status:fixed-pending-verify target:mini-ai),
          $(issue 3 owner:don status:needs-approval)]"
  bsh() { (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r TICKET_OWNER=dkackman \
            SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin" LEAD_TREE="$T/lead" "$@"); }
  git -C "$T/src" worktree add -q --detach "$T/plugin" origin/develop 2>/dev/null
  out="$(bsh lib/board.sh lem)"; rc=$?
  eq  "board.sh: reads the board" 0 "$rc"
  has "board.sh: a fix, unclaimed" "$(printf '1\timplementer:fix\t-\tready\t-')" "$out"
  has "board.sh: mini-ai's claim holds it at wait on lem" "$(printf '2\twait\t-\ttarget:mini-ai holds it\tmini-ai')" "$out"
  has "board.sh: the mini-ai rows offer it" "$(printf '2\ttester:verify\t-\thanded off\tmini-ai')" "$(bsh lib/board.sh mini-ai)"
  FAKE_GH_FAIL=1 bsh lib/board.sh lem >/dev/null 2>&1; rc=$?
  eq  "board.sh: an unreadable board is exit 1" 1 "$rc"
  eq  "board.sh drain: work left" work "$(bsh lib/board.sh drain lem 2>/dev/null)"
  eq  "board.sh frozen: no freeze" 0 "$(bsh lib/board.sh frozen lem 2>/dev/null)"
  eq  "board.sh freeze: no release" "" "$(bsh lib/board.sh freeze lem 2>/dev/null)"
  has "board.sh status: status_board's rows" "#3    status:needs-approval" "$(bsh lib/board.sh status lem 2>/dev/null)"
  FAKE_GH_FAIL=1 bsh lib/board.sh status lem >/dev/null 2>&1; rc=$?
  eq  "board.sh status: unreadable is exit 1" 1 "$rc"
  hk="$(bsh lib/board.sh hk lem lead 2>/dev/null)"
  has "board.sh hk: the freeze" "$(printf 'frozen\t0')" "$hk"
  has "board.sh hk: the status board" "$(printf 'status\t  #3 ')" "$hk"
  fails "board.sh: a bad query is refused" bsh lib/board.sh bogus lem
}
scenario board s_board

# --- A. a design and a verify at once; a deployed fix and a plugin-only one
# verify with no deploy; one gpu slot runs the two verifies one after the
# other; each verify's case lands on main from its own suite tree
s_concurrent() {
  commit dw/core.py "fix the crash (#11)" >/dev/null
  deployed_is_develop
  commit plugins/dw/README "skill wording (#12)" >/dev/null
  board "[$(issue 10 owner:lead idea), $(issue 11 owner:tester status:fixed-pending-verify), $(issue 12 owner:tester status:fixed-pending-verify)]"
  drv_start FAKE_CLAUDE_SLEEP=1.5 FAKE_CLAUDE_SLEEP_design=5 MAX_SESSIONS=3 \
    FAKE_CLAUDE_DO='case "$*" in *"VERIFY session"*) '"$add_case; $close_it"' ;; *"DESIGN session"*) '"$plan_to_don"' ;; esac' --
  until_ 20 started 2; sleep 0.5
  snap_state state-mid.json
  lockowner="$(cat "$T/h/logs/.driver.lock/owner" 2>/dev/null)"
  drv_wait; rc=$?
  eq  "loop: exits cleanly after MAX_SESSIONS" 0 "$rc"
  eq  "loop: three sessions" 3 "$(grep -c '^start' "$FAKE_CLAUDE_LOG")"
  ok  "loop: a design and a verify run at the same time" lt "$(starts design)" "$(ends verify | tail -1)"
  ok  "  (the verify started before the design ended)" lt "$(starts verify | head -1)" "$(ends design)"
  ok  "loop: one GPU slot - the second verify starts after the first ends" lt "$(ends verify | head -1)" "$(starts verify | sed -n 2p)"
  eq  "loop: a deployed fix and a plugin-only one verify with no deploy" "" "$(cat "$T/deploys")"
  eq  "loop: both verified" "CLOSED CLOSED" "$(jq -r '[.["o/r"][] | select(.number == 11 or .number == 12) | .state] | join(" ")' "$T/board.json")"
  eq  "loop: the lock says run-loop (shared-pass detection reads it)" "$drv run-loop" "$lockowner"
  has "loop: the claim label is made once at startup" "gh label create target:lem --repo o/r" "$(cat "$T/gh-calls")"
  eq  "loop: state.json mid-run - the gpu slot is busy" "tester:verify" "$(jq -r '.servers.lem.slots[] | select(.resource == "gpu:lem") | .session.kind' "$T/state-mid.json")"
  eq  "loop: state.json mid-run - and a shared slot" "lead:design" "$(jq -r '.shared.slots[0].session.kind' "$T/state-mid.json")"
  eq  "loop: state.json mid-run - the driver's pid, running" "$drv running" "$(jq -r '"\(.pid) \(.status)"' "$T/state-mid.json")"
  eq  "loop: state.json at exit - stopped" stopped "$(state .status)"
  eq  "loop: state.json at exit - three sessions, their cost" "3 0.75" "$(state '"\(.totals.sessions) \(.totals.cost)"')"
  ok  "loop: state.json has gpu samples" test "$(state '.gpu.lem.series | length')" -ge 1
  eq  "loop: the plugin tree follows develop" "$(git -C "$T/src" rev-parse --short origin/develop)" "$(git -C "$T/plugin" rev-parse --short HEAD)"
  has "loop: a verify runs in its own suite tree" "/.harnest-worktrees/h/item-" "$(awk '$1 == "start" && $3 == "verify" { print $4 }' "$FAKE_CLAUDE_LOG")"
  has "loop: its case landed on main" "regression: tester added case (#11)" "$(git -C "$T/h" log --format=%s main)"
  has "  with the line it added" "S-F911" "$(git -C "$T/h" show main:regression-suite-smoke.md)"
  has "  and the other's" "S-F912" "$(git -C "$T/h" show main:regression-suite-smoke.md)"
  eq  "  and the trees are gone" "" "$(ls "$T/.harnest-worktrees/h" 2>/dev/null)"
  eq  "loop: no audit warnings" "" "$(grep '\[audit\] WARNING' "$T/h/logs/loop.log")"
  eq  "loop: the lock is released at exit" "" "$(ls -d "$T/h/logs/.driver.lock" 2>/dev/null)"
}
scenario concurrent s_concurrent

# --- B. two fixes merge and are handed off while an answer session (a gpu
# session, on a server that runs develop) runs, and lem doesn't run them:
# one deploy, after the answer ends and before either verify
s_deploy() {
  board "[$(issue 20 owner:tester status:needs-info), $(issue 21 owner:don status:needs-approval), $(issue 22 owner:don status:needs-approval)]"
  merge="git -C '$T/seed' pull -q origin develop"
  for i in 21 22; do merge="$merge; echo $i >> '$T/seed/dw/core.py'; git -C '$T/seed' -c user.name=t -c user.email=t@t commit -qam 'fix (#$i)'"; done
  merge="$merge; git -C '$T/seed' push -q origin HEAD:develop"
  handoff="$merge"'; for i in 21 22; do gh issue edit $i --repo o/r --remove-label owner:don --remove-label status:needs-approval --add-label owner:tester --add-label status:fixed-pending-verify; done'
  drv_start LOOP_POLL_SECS=1 FAKE_CLAUDE_SLEEP=1.5 FAKE_CLAUDE_DO="$close_it" FAKE_CLAUDE_FIRST='case "$*" in *"ANSWER session"*) '"$handoff"' ;; esac' -- --once
  until_ 20 deploy_state "draining 21 22"
  snap_state state-mid.json
  drv_wait
  eq  "deploy: exits cleanly" 0 $?
  eq  "deploy: state.json shows the drain and who waits" "draining 21 22" "$(jq -r '"\(.servers.lem.deploy.state) \(.servers.lem.deploy.waiting | join(" "))"' "$T/state-mid.json")"
  eq  "deploy: one deploy for two hand-offs" 1 "$(grep -c 'lem deploy.sh' "$T/deploys")"
  dep="$(awk '{ print $1; exit }' "$T/deploys")"
  ok  "deploy: waits for the running answer session" lt "$(ends answer)" "$dep"
  ok  "deploy: before the first verify" lt "$dep" "$(starts verify | head -1)"
  ok  "deploy: one GPU slot - the verifies run one after the other" lt "$(ends verify | head -1)" "$(starts verify | sed -n 2p)"
  eq  "deploy: both verified" "CLOSED CLOSED" "$(jq -r '[.["o/r"][] | select(.number == 21 or .number == 22) | .state] | join(" ")' "$T/board.json")"
  eq  "deploy: lem runs develop now" "$(git -C "$T/src" rev-parse --short origin/develop)" "$(cat "$T/lem-head")"
  eq  "deploy: state.json has the deploy" "true idle" "$(state '"\(.servers.lem.deploy.last.ok) \(.servers.lem.deploy.state)"')"
  has "deploy: the verify prompt names what lem runs now" "lem is running: develop @ $(cat "$T/lem-head")" "$(cat "$FAKE_CLAUDE_LOG.argv")"
}
scenario deploy s_deploy

# --- C. a deploy that fails twice parks the verify that waits for it (and
# the server stays down, so gpu:lem stays held)
s_deploy_fails() {
  touch "$T/deploy-fails" "$T/health-down"
  commit dw/core.py "fix three (#31)" >/dev/null
  board "[$(issue 31 owner:tester status:fixed-pending-verify)]"
  run DEPLOY_RETRY_SECS=1 DEPLOY_VERIFY_SECS=1 -- --once
  eq  "failed deploy: exits cleanly" 0 $?
  eq  "failed deploy: tried, then once more" 2 "$(grep -c 'lem deploy.sh' "$T/deploys")"
  eq  "failed deploy: parked with Don" "owner:don,status:fixed-pending-verify,status:needs-approval" "$(labels_of 31)"
  has "failed deploy: an environment reason" "Kind:** environment" "$(jq -r '.["o/r"][0].comments[-1].body' "$T/board.json")"
  fails "failed deploy: not counted deployed" grep -q "counting it deployed" "$T/h/logs/loop.log"
  eq  "failed deploy: no session ran" 0 "$(grep -c '^start' "$FAKE_CLAUDE_LOG")"
  eq  "failed deploy: state.json says failed" "failed false" "$(state '"\(.servers.lem.deploy.state) \(.servers.lem.deploy.last.ok)"')"
}
scenario deploy-fails s_deploy_fails

# --- C1. deploy.sh exits 1 although lem came up at develop (its health loop
# raced the restart): counted deployed - no retry, no park, the verify runs
s_deploy_false_fails() {
  touch "$T/deploy-false-fails"
  commit dw/core.py "fix five (#33)" >/dev/null
  board "[$(issue 33 owner:tester status:fixed-pending-verify)]"
  run DEPLOY_RETRY_SECS=1 DEPLOY_VERIFY_SECS=5 FAKE_CLAUDE_DO="$close_it" -- --once
  eq  "false deploy failure: exits cleanly" 0 $?
  eq  "  deployed once, no retry" 1 "$(grep -c 'lem deploy.sh' "$T/deploys")"
  has "  said it counts it deployed" "deploy.sh reported failure but lem is healthy at $(git -C "$T/src" rev-parse --short origin/develop): counting it deployed" "$(cat "$T/h/logs/loop.log")"
  fails "  not parked" grep -q "failed twice" "$T/h/logs/loop.log"
  eq  "  the verify ran" verify "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG")"
  eq  "  state.json: the deploy is ok" "true idle" "$(state '"\(.servers.lem.deploy.last.ok) \(.servers.lem.deploy.state)"')"
}
scenario deploy-false-fails s_deploy_false_fails

# --- C2. a deploy that moves lem's head and then fails (lem stops answering):
# gpu:lem stays held through the retry window and the retry, and after the
# park until lem answers its preflight again; only then does a gpu session
# (a closures pass) start
s_deploy_moves() {
  touch "$T/deploy-moves-fails"
  commit dw/core.py "fix four (#91)" >/dev/null
  board "[$(issue 91 owner:tester status:fixed-pending-verify),
          {\"number\": 95, \"state\": \"CLOSED\", \"stateReason\": \"NOT_PLANNED\", \"labels\": [{\"name\": \"owner:tester\"}, {\"name\": \"wontfix\"}]}]"
  drv_start LOOP_POLL_SECS=1 DEPLOY_RETRY_SECS=2 DEPLOY_VERIFY_SECS=1 MAX_SESSIONS=1 --
  until_ 30 grep -q 'failed twice' "$T/h/logs/loop.log"
  until_ 20 grep -q 'lem still fails its preflight' "$T/h/logs/loop.log"   # a housekeeping pass has checked it
  sleep 2
  eq  "moved then failed: no gpu session through the retry and the park" 0 "$(grep -c '^start' "$FAKE_CLAUDE_LOG")"
  eq  "  the deploy was tried twice" 2 "$(grep -c 'lem deploy.sh' "$T/deploys")"
  eq  "  state.json: what lem runs is unknown, the gate failed" "unknown failed" "$(state '"\(.servers.lem.deployed) \(.servers.lem.deploy.state)"')"
  has "  said the preflight still fails" "lem still fails its preflight" "$(cat "$T/h/logs/loop.log")"
  python3 -c 'import time; print(time.time())' > "$T/health-back"; rm -f "$T/health-down"
  drv_wait
  eq  "moved then failed: exits cleanly" 0 $?
  eq  "  parked the verify with Don" "owner:don,status:fixed-pending-verify,status:needs-approval" "$(labels_of 91)"
  has "  gpu:lem free again once lem answers" "lem passes its preflight again" "$(cat "$T/h/logs/loop.log")"
  eq  "  then the closures pass ran" closures "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG")"
  ok  "  only after lem answered" lt "$(cat "$T/health-back")" "$(starts closures)"
  eq  "  and the head was read again" "$(git -C "$T/src" rev-parse --short origin/develop)" "$(state .servers.lem.deployed)"
}
scenario deploy-moves s_deploy_moves

# --- C3. SIGTERM while a deploy runs: the driver waits for it, holding the
# lock, then exits
s_sigterm_deploy() {
  echo 3 > "$T/deploy-sleep"
  commit dw/core.py "fix five (#101)" >/dev/null
  board "[$(issue 101 owner:tester status:fixed-pending-verify)]"
  drv_start LOOP_POLL_SECS=1 SESSION_KILL_SECS=1 CHILD_DRIVER_KILL_SECS=1 -- --once
  until_ 20 test -s "$T/deploys"
  kill -TERM "$drv"
  sleep 1
  lock_mid="$(ls -d "$T/h/logs/.driver.lock" 2>/dev/null)"
  drv_wait 20; rc=$?
  eq  "SIGTERM mid-deploy: exits 143" 143 "$rc"
  has "  said it waits for the deploy" "waiting for the deploy to lem to finish" "$(cat "$T/h/logs/loop.log")"
  eq  "  kept the lock while it waited" "$T/h/logs/.driver.lock" "$lock_mid"
  eq  "  the deploy ran to its end" 1 "$(grep -c 'deploy.sh ended' "$T/deploy-ends" 2>/dev/null)"
  has "  then said so" "the deploy to lem finished" "$(cat "$T/h/logs/loop.log")"
  eq  "  no verify started" 0 "$(grep -c '^start' "$FAKE_CLAUDE_LOG")"
  eq  "  the lock is released at exit" "" "$(ls -d "$T/h/logs/.driver.lock" 2>/dev/null)"
}
scenario sigterm-deploy s_sigterm_deploy

# --- C4. a verify that starts while a spec runs (on a free slot) still gets
# a plugin tree refreshed to develop; the spec reads a tree of its own
s_trees() {
  board "[$(issue 110 owner:tester status:needs-spec), $(issue 111 owner:don status:needs-approval)]"
  skill="git -C '$T/seed' pull -q origin develop; echo s >> '$T/seed/plugins/dw/README'"
  skill="$skill; git -C '$T/seed' -c user.name=t -c user.email=t@t commit -qam 'skill wording (#111)'; git -C '$T/seed' push -q origin HEAD:develop"
  skill="$skill"'; gh issue edit 111 --repo o/r --remove-label owner:don --remove-label status:needs-approval --add-label owner:tester --add-label status:fixed-pending-verify'
  where='d="$(printf "%s" "$*" | grep -oE -- "--plugin-dir [^ ]+" | head -1 | cut -d" " -f2)"; echo "$kind $d $(git -C "$d" rev-parse --short HEAD)" >> '"'$T/trees'"
  run LOOP_POLL_SECS=1 FAKE_CLAUDE_SLEEP=0.5 FAKE_CLAUDE_SLEEP_spec=5 \
    FAKE_CLAUDE_FIRST="$where; case \"\$*\" in *\"SPEC session\"*) $skill ;; esac" -- --once
  eq  "trees: exits cleanly" 0 $?
  dev="$(git -C "$T/src" rev-parse --short origin/develop)"
  eq  "trees: the verify loads the gpu tree at develop, refreshed beside the spec" "verify $T/plugin/plugins/dw $dev" "$(grep '^verify' "$T/trees")"
  has "trees: the spec loads a tree of its own" "spec $T/plugin-free/plugins/dw" "$(grep '^spec' "$T/trees")"
  ok  "  (the verify started while the spec ran)" lt "$(starts verify)" "$(ends spec)"
}
scenario trees s_trees

# --- D. a GitHub outage starts nothing; a lock left by a dead driver is taken over
s_outage() {
  mkdir "$T/h/logs/.driver.lock"; echo "999999 run-loop" > "$T/h/logs/.driver.lock/owner"
  board "[$(issue 41 owner:implementer)]"
  run FAKE_GH_FAIL=1 -- --once
  eq  "outage: exits cleanly" 0 $?
  eq  "outage: no session" 0 "$(grep -c '^start' "$FAKE_CLAUDE_LOG")"
  eq  "outage: state.json says the board is unreadable" false "$(state .board_readable)"
  has "stale lock: taken over" "[lock] taking over a stale lock from '999999 run-loop'" "$(cat "$T/h/logs/loop.log")"
  eq  "stale lock: released at exit" "" "$(ls -d "$T/h/logs/.driver.lock" 2>/dev/null)"
}
scenario outage s_outage

# --- E. stop-after-cycle.mini-ai stops mini-ai only: its lock goes, lem's
# stays and lem keeps working; an unclaimed design goes to lem (shared)
s_stop_one() {
  board "[$(issue 50 owner:implementer), $(issue 51 owner:lead idea)]"
  touch "$T/h/logs/stop-after-cycle.mini-ai"
  drv_start FAKE_CLAUDE_SLEEP=2 MAX_SESSIONS=2 FAKE_CLAUDE_DO="$close_it" -- --servers lem,mini-ai
  until_ 20 started 1
  until_ 5 test ! -e "$T/h/logs/.driver.lock.mini-ai"
  eq  "stop one server: the mini-ai lock is released" "" "$(ls -d "$T/h/logs/.driver.lock.mini-ai" 2>/dev/null)"
  eq  "  and its flag consumed" "" "$(ls "$T/h/logs/stop-after-cycle.mini-ai" 2>/dev/null)"
  ok  "  the driver keeps running" kill -0 "$drv"
  eq  "  holding lem's lock" "$drv run-loop" "$(cat "$T/h/logs/.driver.lock/owner" 2>/dev/null)"
  drv_wait
  eq  "stop one server: exits cleanly" 0 $?
  eq  "stop one server: lem ran the fix and the design" "design lem fix lem" "$(awk '$1 == "start" { print $3, $5 }' "$FAKE_CLAUDE_LOG" | sort | tr '\n' ' ' | sed 's/ $//')"
  has "stop one server: said so" "mini-ai: no longer driven (stop-after-cycle)" "$(cat "$T/h/logs/loop.mini-ai.log")"
}
scenario stop-one s_stop_one

# --- F. SIGTERM: the sessions are killed within the bounds, the lock released
s_sigterm() {
  board "[$(issue 60 owner:implementer), $(issue 61 owner:tester status:fixed-pending-verify)]"
  drv_start FAKE_CLAUDE_SLEEP=30.7 SESSION_KILL_SECS=2 CHILD_DRIVER_KILL_SECS=3 -- --once
  until_ 20 started 2
  kill -TERM "$drv"
  k0=$SECONDS
  drv_wait 10; rc=$?
  eq  "SIGTERM: the driver exits 143" 143 "$rc"
  ok  "SIGTERM: within the kill bounds" test $((SECONDS - k0)) -le 5
  eq  "SIGTERM: no claude child is left" "" "$(pgrep -f 'sleep 30.7')"
  eq  "SIGTERM: no item is left" "" "$(pgrep -f "$T/h/lib/run-item.sh")"
  eq  "SIGTERM: the lock is released" "" "$(ls -d "$T/h/logs/.driver.lock" 2>/dev/null)"
  eq  "SIGTERM: state.json says stopped" stopped "$(state .status)"
  pkill -f 'sleep 30.7' 2>/dev/null
}
scenario sigterm s_sigterm

# --- G. a rate limit pauses every dispatch: the design that becomes ready
# while the fix's session is turned away starts only after the reset
s_ratelimit() {
  board "[$(issue 70 owner:implementer), $(issue 71 owner:don status:needs-approval)]"
  to_design='gh issue edit 71 --repo o/r --remove-label owner:don --remove-label status:needs-approval --add-label owner:lead --add-label idea'
  drv_start LOOP_POLL_SECS=1 FAKE_CLAUDE_SLEEP=0 MAX_SESSIONS=2 FAKE_CLAUDE_REJECT="$T/rejected" FAKE_CLAUDE_REJECT_IN=3 \
    FAKE_CLAUDE_ON_REJECT="$to_design" FAKE_CLAUDE_DO="$close_it" --
  until_ 20 test -s "$T/rejected"; sleep 1.2
  snap_state state-mid.json
  drv_wait
  eq  "rate limit: exits cleanly" 0 $?
  eq  "rate limit: state.json says paused" paused-rate-limit "$(jq -r .status "$T/state-mid.json")"
  has "rate limit: logged" "[loop] rate limit rejected: no session starts until" "$(cat "$T/h/logs/loop.log")"
  ok  "rate limit: the design starts after the reset, not at the next poll" ge_by "$(cat "$T/rejected")" "$(starts design)" 2.5
}
scenario ratelimit s_ratelimit

# --- H. the standing task: only once lem has nothing queued and the gap has
# passed; never while the gap hasn't
s_task() {
  board "[$(issue 80 owner:tester status:fixed-pending-verify)]"
  run FAKE_CLAUDE_SLEEP=0.5 FAKE_CLAUDE_DO='case "$*" in *"VERIFY session"*) '"$close_it"' ;; esac' TESTER_TASK_GAP_SECS=0 -- --once
  eq  "standing task: exits cleanly" 0 $?
  eq  "standing task: the verify, then the task" "verify task" "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG" | tr '\n' ' ' | sed 's/ $//')"
  ok  "standing task: only after the verify ended (lem idle, nothing queued)" lt "$(ends verify)" "$(starts task)"
  : > "$FAKE_CLAUDE_LOG"
  board "[]"
  run TESTER_TASK_GAP_SECS=3600 -- --once
  eq  "standing task: not before the gap has passed" "" "$(grep '^start' "$FAKE_CLAUDE_LOG")"
  # a wontfix closure the tester hasn't seen gets its own closures session
  board '[{"number": 85, "state": "CLOSED", "stateReason": "NOT_PLANNED", "labels": [{"name": "owner:tester"}, {"name": "wontfix"}]}]'
  run TESTER_TASK_GAP_SECS=3600 -- --once
  eq  "closures: one closures session" "closures" "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG")"
  eq  "closures: marked seen" 85 "$(cat "$T/h/logs/closures-seen" 2>/dev/null)"
}
scenario task s_task

# --- I. two suite writers at once (a spec on a free slot, a verify on the gpu
# slot) add a case at the same place: one lands, the other conflicts and is
# kept on a branch, said in the log and in state.json
s_suite_conflict() {
  board "[$(issue 130 owner:tester status:needs-spec), $(issue 131 owner:tester status:fixed-pending-verify)]"
  run FAKE_CLAUDE_SLEEP=1 FAKE_CLAUDE_DO="$add_case" -- --once
  eq  "suite conflict: exits cleanly" 0 $?
  eq  "suite conflict: the spec and the verify ran at once" "spec verify" "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG" | sort | tr '\n' ' ' | sed 's/ $//')"
  eq  "suite conflict: one landed" 1 "$(git -C "$T/h" log --format=%s main | grep -c 'regression: tester added case')"
  eq  "suite conflict: the other is kept on a branch" 1 "$(git -C "$T/h" branch --list 'suite-conflict/*' | wc -l | tr -d ' ')"
  has "suite conflict: said loudly" "[audit] WARNING: tester:#13" "$(cat "$T/h/logs/loop.log")"
  eq  "suite conflict: state.json has it for Don" "conflict" "$(state '.suite.problems[0].result')"
  has "  with its branch" "suite-conflict/item-" "$(state '.suite.problems[0].branch')"
}
scenario suite-conflict s_suite_conflict

# --- J. the curator: a suite-change request runs in a tree, and its approved
# removal lands on main at info level, under the curator's land note
s_curator() {
  board "[$(issue 160 owner:tester status:fixed-pending-verify docs-review)]" '[{"number": 5, "state": "OPEN", "title": "drop a case", "author": {"login": "dkackman"}, "labels": [{"name": "suite"}]}]'
  git -C "$T/h" show main:regression-suite-smoke.md | head -1 > /dev/null
  run FAKE_CLAUDE_DO='case "$*" in *"REVIEW session for suite-change request #5"*) sed -i "" "\$d" regression-suite-smoke.md; gh issue close 5 --repo h/r --reason completed ;; esac' -- --once
  eq  "curator: exits cleanly" 0 $?
  eq  "curator: one curator session (and the docs review)" "docs other" "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG" | sort | tr '\n' ' ' | sed 's/ $//')"
  has "curator: ran in its own tree" "/.harnest-worktrees/h/item-" "$(awk '$1 == "start" && $3 == "other" { print $4 }' "$FAKE_CLAUDE_LOG")"
  rtree="$(awk '$1 == "start" && $3 == "docs" { print $4 }' "$FAKE_CLAUDE_LOG")"
  case "$rtree" in "$T/plugin-review-s"[0-9]*) rtree_ok=1 ;; *) rtree_ok="$rtree" ;; esac
  eq  "reviewer: reads a merged tree of its own, not the tester's plugin tree" 1 "$rtree_ok"
  has "  at develop" "reviewer tree: origin/develop @ $(git -C "$T/src" rev-parse --short origin/develop) ($rtree)" "$(cat "$T/h/logs/loop.log")"
  fails "  removed when the review ended" test -e "$rtree"
  eq  "curator: its change landed on main" "curator: applied h/r#5" "$(git -C "$T/h" log -1 --format=%s main)"
  has "curator: the removal is logged as approved" "[audit] curator removed lines from regression-suite-smoke.md" "$(cat "$T/h/logs/loop.log")"
  eq  "curator: no warning" "" "$(grep '\[audit\] WARNING' "$T/h/logs/loop.log")"
}
scenario curator s_curator

# --- K. the nightly regression: once due, it waits for the gpu slot, runs as
# a child under the loop's own lock, once a day
s_nightly() {
  printf '# tiny\n## Fixtures\nnone\n### S-F001 — first\nsteps\n' > "$T/h/regression-suite-tiny.md"
  git -C "$T/h" add regression-suite-tiny.md; git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm tiny
  board "[$(issue 140 owner:tester status:fixed-pending-verify)]"
  nightly=(REGRESSION_NIGHTLY_AT=0 "REGRESSION_NIGHTLY_LEVEL=smoke regression-suite-tiny.md" CASES_PER_SESSION=0)
  run "${nightly[@]}" FAKE_CLAUDE_SLEEP=0.5 FAKE_CLAUDE_DO='case "$*" in *"VERIFY session"*) '"$close_it"' ;; esac' -- --once
  eq  "nightly: exits cleanly" 0 $?
  has "nightly: ran" "[nightly] run-regression.sh smoke regression-suite-tiny.md" "$(cat "$T/h/logs/loop.log")"
  has "nightly: under the loop's lock, not waiting on it" "run-regression runs under" "$(cat "$T/h/logs/loop.log")"
  has "nightly: the level ran, logged apart" "regression run (" "$(cat "$T/h/logs/nightly-regression.log")"
  eq  "nightly: the verify ran too" 1 "$(grep -c '^start [0-9.]* verify' "$FAKE_CLAUDE_LOG")"
  v0="$(starts verify)" v1="$(ends verify)" r0="$(awk '$1 == "start" && $3 == "other" { print $2; exit }' "$FAKE_CLAUDE_LOG")"
  if lt "$v0" "$r0"; then ok "nightly: never beside a gpu session" lt "$v1" "$r0"
  else ok "nightly: never beside a gpu session" lt "$(awk '$1 == "end" && $3 == "other" { t = $2 } END { print t }' "$FAKE_CLAUDE_LOG")" "$v0"; fi
  run "${nightly[@]}" -- --once
  eq  "nightly: once a day" 1 "$(grep -c '\[nightly\] run-regression' "$T/h/logs/loop.log")"
}
scenario nightly s_nightly

# --- L. DRAIN=1 works the board and exits once only deferred issues are left;
# --only runs only the queues it names
s_drain() {
  board "[$(issue 150 owner:implementer), $(issue 151 owner:don parked)]"
  run DRAIN=1 FAKE_CLAUDE_DO="$close_it" --
  eq  "drain: exits cleanly" 0 $?
  eq  "drain: the fix ran" "fix" "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG")"
  has "drain: then stops" "[loop] drain: nothing left but deferred issues, exiting" "$(cat "$T/h/logs/loop.log")"
  : > "$FAKE_CLAUDE_LOG"
  board "[$(issue 152 owner:implementer), $(issue 153 owner:lead idea)]"
  run -- --once --only lead:design
  eq  "--only: only the queues named" "design" "$(awk '$1 == "start" { print $3 }' "$FAKE_CLAUDE_LOG")"
}
scenario drain s_drain

wait
for s in $scenarios; do
  cat "$T/$s.out"
  if read -r p f < "$T/$s/tally" 2>/dev/null; then _pass=$((_pass + p)); _fail=$((_fail + f))
  else _fail=$((_fail + 1)); echo "  FAIL: scenario $s did not finish"; fi
done
finish
