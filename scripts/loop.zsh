#!/bin/zsh
# Start, stop and look at the loop driver (python3 -m harness.drivers.loop,
# docs/harness/running.md). One driver process runs every loop server.
#
#   scripts/loop.zsh start [driver args]   start it detached; refuses while a loop already runs
#   scripts/loop.zsh stop                  graceful: running sessions finish, then it exits (waits for that)
#   scripts/loop.zsh stop --now            kill -TERM: sessions are stopped where they are
#   scripts/loop.zsh restart [driver args] stop (graceful), then start
#   scripts/loop.zsh status                pid, state, running sessions, today's spend
#   scripts/loop.zsh log                   follow logs/loop.log
#   scripts/loop.zsh dashboard             start the dashboard if it is not running, and print its address
#
# start and restart also bring the dashboard up (dashboard/serve.py, port
# DASHBOARD_PORT or 8780) when none is running; stop leaves it alone, since
# it is read-only and useful with the loop down.
#
# Knobs pass through from the environment, and driver args from the command line:
#   DRAIN=1 scripts/loop.zsh start                   # exit once only deferred issues are left
#   DAY_BUDGET_USD=60 scripts/loop.zsh start         # with a daily spend cap
#   scripts/loop.zsh start --servers lem             # lem only
#   scripts/loop.zsh restart --stop-now              # restart without waiting out the sessions
#
# The driver's own output goes to logs/loop.stdout; logs/loop.log is the
# stream to read. Run it from anywhere: it cds to the checkout.
emulate -L zsh
setopt err_return no_unset pipe_fail

repo="${0:A:h:h}"
cd "$repo"
logs="$repo/logs"
out="$logs/loop.stdout"

# The driver's pid, or nothing. The process is found by its command line, so
# a stale state.json or lock from a killed driver is not mistaken for one.
# Only a process whose working directory is this checkout counts: the test
# suite and other checkouts run drivers of their own.
here() {
  local p
  for p in "$@"; do
    [[ "$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" == "$repo" ]] && print -r -- "$p"
  done
  return 0
}
driver_pid() { here $(pgrep -f '[Pp]ython.* -m harness\.drivers\.loop' || true) | head -n 1 }
bash_loops() {
  local p
  for p in $(here $(pgrep -f 'run-loop\.sh' || true)); do ps -o pid=,command= -p "$p"; done
  return 0
}

dash_pid() { pgrep -f 'dashboard/serve\.py' | head -n 1 || true }

say() { print -r -- "$@" }
die() { print -u2 -r -- "loop.zsh: $*"; exit 1 }

start() {
  local pid; pid="$(driver_pid)"
  [[ -z "$pid" ]] || die "the driver is already running (pid $pid); use restart, or stop first"
  [[ -z "$(bash_loops)" ]] || die "a bash run-loop.sh is running; stop it first:
$(bash_loops)"
  mkdir -p "$logs"
  # Left over from a stop that was asked for and never consumed: the new
  # driver would stop that server at once.
  rm -f "$logs"/stop-after-cycle*(N)
  nohup python3 -m harness.drivers.loop "$@" >> "$out" 2>&1 &!
  local i
  for i in {1..20}; do
    sleep 0.5
    pid="$(driver_pid)"
    [[ -z "$pid" ]] || break
  done
  if [[ -z "$pid" ]]; then
    print -u2 -r -- "loop.zsh: the driver did not stay up; the end of $out:"
    tail -n 15 "$out" >&2
    exit 1
  fi
  say "started: pid $pid${*:+ ($*)}"
  dashboard
  say "  follow it:  scripts/loop.zsh log     state:  scripts/loop.zsh status"
}

dashboard() {
  local port="${DASHBOARD_PORT:-8780}" pid
  pid="$(dash_pid)"
  if [[ -n "$pid" ]]; then say "dashboard: already running (pid $pid)"; return 0; fi
  mkdir -p "$logs"
  nohup python3 dashboard/serve.py --port "$port" >> "$logs/dashboard.stdout" 2>&1 &!
  sleep 1
  pid="$(dash_pid)"
  if [[ -z "$pid" ]]; then
    say "dashboard: did not start (the loop is unaffected); see $logs/dashboard.stdout"
    return 0
  fi
  say "dashboard: started (pid $pid) at http://127.0.0.1:$port"
}

# stop [--now]: graceful by default. A stop flag per server the driver holds
# (logs/.driver.lock<suffix> -> logs/stop-after-cycle<suffix>): its sessions
# finish, its lock is released, and the driver exits when no server is left.
stop() {
  local pid; pid="$(driver_pid)"
  if [[ -z "$pid" ]]; then say "not running"; return 0; fi
  if [[ "${1:-}" == --now ]]; then
    kill -TERM "$pid"
    say "sent TERM to pid $pid; its sessions are being stopped"
  else
    local lock sfx n=0
    for lock in "$logs"/.driver.lock*(N/); do
      sfx="${lock:t}"; sfx="${sfx#.driver.lock}"
      [[ "$sfx" != *.stale.* ]] || continue
      # only a server this driver holds: another lock is some other run
      [[ "$(cut -d' ' -f1 "$lock/owner" 2>/dev/null)" == "$pid" ]] || continue
      touch "$logs/stop-after-cycle$sfx"; n=$((n + 1))
    done
    (( n > 0 )) || { kill -TERM "$pid"; say "no server lock held yet; sent TERM to pid $pid" }
    (( n == 0 )) || say "asked pid $pid to stop: running sessions finish first (Ctrl-C stops the waiting, not the driver)"
  fi
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5; waited=$((waited + 5))
    (( waited % 60 )) || say "  still stopping after ${waited}s: $(running_line)"
  done
  rm -f "$logs"/stop-after-cycle*(N)
  say "stopped"
}

running_line() {
  jq -r '[.servers[].slots[]?, .shared.slots[]? | .session | select(. != null)
          | (.label // .item // .key // tostring)] | unique
         | if length == 0 then "no session running" else "running: " + join(", ") end' \
    "$logs/loop/state.json" 2>/dev/null || print -r -- "state unreadable"
}

status() {
  local pid; pid="$(driver_pid)"
  if [[ -z "$pid" ]]; then
    say "driver: not running"
    [[ -z "$(bash_loops)" ]] || { say "but a bash run-loop.sh is:"; bash_loops }
  else
    say "driver: pid $pid, up $(ps -o etime= -p "$pid" | tr -d ' ')"
    jq -r '"state:  \(.status)   sessions this run: \(.totals.sessions // 0)   cost: $\(.totals.cost // 0)   closed: \(.totals.closed // 0)",
           (.servers | to_entries[] | "  \(.key): deployed \(.value.deployed // "?")   deploy \(.value.deploy.state // "?")")' \
      "$logs/loop/state.json" 2>/dev/null || say "state:  logs/loop/state.json not readable yet"
    say "  $(running_line)"
  fi
  local dpid; dpid="$(dash_pid)"
  if [[ -n "$dpid" ]]; then say "dashboard: running (pid $dpid), http://127.0.0.1:${DASHBOARD_PORT:-8780}"
  else say "dashboard: not running (scripts/loop.zsh dashboard starts it)"; fi
  local flag
  for flag in "$logs"/stop-after-cycle*(N); do say "stop asked for: ${flag:t}"; done
  if [[ -r "$logs/spend.tsv" ]]; then
    say "spent today: \$$(awk -F'\t' -v d="$(date +%F)" '$1 == d { s += $3; n++ } END { printf "%.2f in %d sessions", s, n }' "$logs/spend.tsv")${DAY_BUDGET_USD:+ (this shell has DAY_BUDGET_USD=$DAY_BUDGET_USD)}"
  fi
}

cmd="${1:-status}"
(( $# == 0 )) || shift
case "$cmd" in
  start) start "$@" ;;
  stop) stop "$@" ;;
  restart)
    if [[ "${1:-}" == --stop-now ]]; then shift; stop --now; else stop; fi
    start "$@" ;;
  status) status ;;
  dashboard) dashboard ;;
  log|logs) exec tail -n 40 -f "$logs/loop.log" ;;
  *) print -u2 -r -- "usage: scripts/loop.zsh start [driver args] | stop [--now] | restart [--stop-now] [driver args] | status | log | dashboard"; exit 2 ;;
esac
