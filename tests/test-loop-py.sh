#!/usr/bin/env bash
# The Python loop driver (harness/drivers/loop.py, R17) end to end, offline,
# in the style of test-regression-py.sh: a throwaway git origin with a develop
# branch, a clone for SOURCE_DIR, a copy of this harness as its own repo, and
# fakes for gh (tests/fake-gh.py over a JSON board), ssh (deployed heads and
# deploy.sh, recorded), curl (/api/health) and claude (sleeps, logs when each
# session starts and ends). Every run is bounded: --once, MAX_SESSIONS or a
# signal. The sessions sleep 0-2 s, so the whole file stays well under 20 s.
. "$(dirname "$0")/lib.sh"

# --- fixtures
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
mkdir -p "$T/seed/plugins/dw" "$T/seed/dw"; echo x > "$T/seed/plugins/dw/README"; echo x > "$T/seed/dw/core.py"
git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
git clone -q -b develop "$T/origin.git" "$T/src"
git clone -q -b develop "$T/origin.git" "$T/src-mini-ai"
base="$(git -C "$T/src" rev-parse --short HEAD)"
# commit <file> <message>: a merge to develop, as an implementer's hand-off makes
commit() {
  git -C "$T/seed" pull -q origin develop 2>/dev/null
  echo "$RANDOM" >> "$T/seed/$1"
  git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm "$2"
  git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
  git -C "$T/seed" rev-parse --short HEAD
}

mkdir "$T/h"
(cd "$HARNEST" && tar cf - --exclude ./logs --exclude ./.git --exclude ./.env .) | (cd "$T/h" && tar xf -)
rm -f "$T/h"/regression-results/*.jsonl "$T/h"/regression-results/*/*.jsonl
git -C "$T/h" init -q -b main && git -C "$T/h" add -A && git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm h

ln -s "$HARNEST/tests/fake-gh.py" "$T/bin/gh"
# ssh: the deployed head is $T/<server>-head; deploy.sh is recorded (with the
# time) and moves it to develop, or fails while $T/deploy-fails exists
cat > "$T/bin/ssh" <<EOS
#!/usr/bin/env bash
srv=lem; case "\$*" in *mini-ai*) srv=mini-ai ;; esac
case "\$*" in
  *deploy.sh*)
    echo "\$(python3 -c 'import time; print(time.time())') \$srv deploy.sh" >> "$T/deploys"
    [ ! -e "$T/deploy-fails" ] || { echo "deploy: health check timed out"; exit 1; }
    git -C "$T/src" fetch -q origin develop; git -C "$T/src" rev-parse --short origin/develop > "$T/\$srv-head"
    echo "deployed develop" ;;
  *) echo "develop @ \$(cat "$T/\$srv-head" 2>/dev/null || echo 0000000)" ;;
esac
EOS
# curl: /api/health names the server the URL is on, with one idle worker
cat > "$T/bin/curl" <<EOS
#!/usr/bin/env bash
case "\$*" in
  *mini-ai*) echo '{"status":"ok","device":"mps","hostname":"mini-ai.lan","workers":[{"device":"mps","current_job":null}]}' ;;
  *) echo '{"status":"ok","device":"cuda","hostname":"lem","workers":[{"device":"cuda:0","current_job":null},{"device":"cuda:1","current_job":null}]}' ;;
esac
EOS
# claude: logs "start|end <epoch> <kind> <cwd>" around FAKE_CLAUDE_SLEEP
# seconds, then runs FAKE_CLAUDE_DO (an agent's action) and reports a result
cat > "$T/bin/claude" <<'EOS'
#!/usr/bin/env bash
kind=other
case "$*" in
  *"VERIFY session"*) kind=verify ;; *"ANSWER session"*) kind=answer ;; *"SPEC session"*) kind=spec ;;
  *"TASK session"*) kind=task ;; *"CLOSURES session"*) kind=closures ;; *"fix session"*) kind=fix ;;
  *"TRIAGE session"*) kind=triage ;; *"DESIGN"*|*"design session"*) kind=design ;; *"DOCS REVIEW"*) kind=docs ;;
esac
now() { python3 -c 'import time; print(time.time())'; }
echo "start $(now) $kind $PWD $DW_TARGET_SEEN" >> "$FAKE_CLAUDE_LOG"
echo "claude $*" >> "$FAKE_CLAUDE_LOG.argv"
echo "{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"claude-fake\"}"
# FAKE_CLAUDE_REJECT: a marker file; the first session is turned away by the
# rate limit (resetting FAKE_CLAUDE_REJECT_IN seconds from now) and makes it
if [ -n "${FAKE_CLAUDE_REJECT:-}" ] && [ ! -e "$FAKE_CLAUDE_REJECT" ]; then
  now > "$FAKE_CLAUDE_REJECT"
  echo "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"rejected\",\"rateLimitType\":\"five_hour\",\"isUsingOverage\":false,\"resetsAt\":$(( $(date +%s) + ${FAKE_CLAUDE_REJECT_IN:-0} - 60 ))}}"
  [ -z "${FAKE_CLAUDE_ON_REJECT:-}" ] || eval "$FAKE_CLAUDE_ON_REJECT" >/dev/null
  echo '{"type":"result","subtype":"success","num_turns":1,"duration_ms":10,"total_cost_usd":0,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}'
  exit 0
fi
sleep "${FAKE_CLAUDE_SLEEP:-0}"
[ -z "${FAKE_CLAUDE_DO:-}" ] || eval "$FAKE_CLAUDE_DO" >/dev/null 2>&1
echo "end $(now) $kind $PWD" >> "$FAKE_CLAUDE_LOG"
echo '{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.25,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}'
EOS
chmod +x "$T/bin/ssh" "$T/bin/curl" "$T/bin/claude"
export FAKE_CLAUDE_LOG="$T/claude-calls" FAKE_GH_LOG="$T/gh-calls"

board() { printf '{"o/r": %s, "h/r": []}\n' "$1" > "$T/board.json"; }
labels_of() { jq -r --arg n "$1" '.["o/r"][] | select((.number|tostring) == $n) | [.labels[].name] | sort | join(",")' "$T/board.json"; }
issue() { # issue <n> <label>...: an open issue as the fake board holds it
  local n="$1" l out=""; shift
  for l in "$@"; do out="$out${out:+, }{\"name\": \"$l\"}"; done
  printf '{"number": %s, "state": "OPEN", "title": "issue %s", "labels": [%s]}' "$n" "$n" "$out"
}
fresh() { # a clean slate for one run
  rm -rf "$T/h/logs"; mkdir -p "$T/h/logs"
  : > "$FAKE_CLAUDE_LOG"; : > "$FAKE_CLAUDE_LOG.argv"; : > "$T/deploys"; rm -f "$T/deploy-fails"
}
# drv [VAR=value ...] -- <driver args>: the real driver over the fixtures,
# in the background ($drv is its pid); its output goes to $T/loop.out
drv_start() {
  local -a vars=()
  while [ "$1" != -- ]; do vars+=("$1"); shift; done; shift
  (cd "$T/h" && exec env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r HARNESS_REPO=h/r TICKET_OWNER=dkackman \
     SOURCE_DIR="$T/src" PLUGIN_TREE="$T/plugin" LEAD_TREE="$T/lead" SESSION_RETRY_PAUSE_SECS=0 \
     LOOP_POLL_SECS=1 LOOP_HEALTH_SECS=1 TESTER_TASK_GAP_SECS=999999 SNAPSHOT_TTL_SECS=0 \
     ${vars[@]+"${vars[@]}"} python3 -m harness.drivers.loop "$@") > "$T/loop.out" 2>&1 &
  drv=$!
}
# drv_wait [secs]: wait for it (default 30 s), killing it past that
drv_wait() {
  local i
  for i in $(seq 1 $(( ${1:-30} * 10 ))); do kill -0 "$drv" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$drv" 2>/dev/null; then kill -KILL "$drv"; echo "driver timed out" >> "$T/loop.out"; fi
  wait "$drv"
}
run() { drv_start "$@"; drv_wait; }
# starts <kind>: the start times of that kind's sessions; ends likewise
starts() { awk -v k="$1" '$1 == "start" && $3 == k { print $2 }' "$FAKE_CLAUDE_LOG"; }
ends() { awk -v k="$1" '$1 == "end" && $3 == k { print $2 }' "$FAKE_CLAUDE_LOG"; }
lt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }
state() { jq -r "$1" "$T/h/logs/loop/state.json"; }

# --- lib/board.sh: classify rows with the claim holder, and the queries
echo "$base" > "$T/lem-head"
board "[$(issue 1 owner:implementer), $(issue 2 owner:tester status:fixed-pending-verify target:mini-ai),
        $(issue 3 owner:don status:needs-approval)]"
mkdir -p "$T/h/logs"
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
fails "board.sh: a bad query is refused" bsh lib/board.sh bogus lem
git -C "$T/src" worktree remove --force "$T/plugin"

finish
