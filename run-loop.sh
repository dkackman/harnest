#!/usr/bin/env bash
# Drives the implementer and tester Claude Code agents in strictly alternating
# cycles. Both agents communicate only through mcp-feedback.md.
#
#   ./run-loop.sh                       # run forever
#   MAX_CYCLES=3 SLEEP_SECS=60 ./run-loop.sh
#   MODEL=sonnet ./run-loop.sh          # default is opus
#   DW_URL=... DW_TOKEN=... ./run-loop.sh   # dw MCP endpoint handed to the tester
#   tail -f logs/loop.log               # watch from another terminal
#
# The implementer runs inside the diffusers-workflow source checkout; the tester
# runs inside this repo, which contains no code. That working-directory split is
# what keeps the tester a pure MCP consumer.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/diffusers-workflow}"
TICKETS="$REPO/mcp-feedback.md"
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
SLEEP_SECS="${SLEEP_SECS:-120}"
MAX_CYCLES="${MAX_CYCLES:-0}"   # 0 = run forever
MODEL="${MODEL:-opus}"         # passed to both agents as --model
DW_URL="${DW_URL:-http://192.168.1.194:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"     # dev token; the server is LAN-only
PLUGIN_DIR="$SOURCE_DIR/plugins/dw"

[ -d "$SOURCE_DIR" ] || { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }
[ -f "$TICKETS" ]    || { echo "ticket file not found: $TICKETS" >&2; exit 1; }
[ -d "$PLUGIN_DIR" ] || { echo "dw plugin source not found: $PLUGIN_DIR" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
mkdir -p "$LOGS"

ts() { date '+%H:%M:%S'; }

# The tester's cwd has no MCP config of its own, so the dw server is passed
# explicitly. --strict-mcp-config means dw is the *only* server it sees.
# --plugin-dir loads the dw plugin live from the implementer's working tree
# instead of the frozen copy in ~/.claude/plugins/cache, so skill fixes are
# testable without a reinstall. Tool schemas come from the server and are
# always fresh.
TESTER_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  --plugin-dir "$PLUGIN_DIR"
)

# run_agent <name> <cwd> <prompt> [extra claude flags...]
# Streams the agent's output to the terminal, its own log, and the combined log.
run_agent() {
  local name="$1" dir="$2" prompt="$3"; shift 3
  echo "=== $(ts) cycle $cycle: $name ($MODEL) ===" | tee -a "$LOGS/loop.log"
  (cd "$dir" && claude -p "$prompt" --model "$MODEL" --dangerously-skip-permissions "$@" 2>&1) \
    | tee -a "$LOGS/$name.log" \
    | sed -u "s/^/[$name] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[$name] cycle failed, continuing" | tee -a "$LOGS/loop.log"
}

# One line per ticket: ID  status  owner  title
status_board() {
  awk '
    /^## T[0-9]+/            { if (id != "" && id != "T000") printf "  %-5s %-22s %-12s %s\n", id, st, own, title; id=$2; st=own=title="" }
    /^- \*\*status:\*\*/     { sub(/^- \*\*status:\*\* */, ""); st=$0 }
    /^- \*\*owner:\*\*/      { sub(/^- \*\*owner:\*\* */, ""); own=$0 }
    /^- \*\*title:\*\*/      { sub(/^- \*\*title:\*\* */, ""); title=$0 }
    END                      { if (id != "" && id != "T000") printf "  %-5s %-22s %-12s %s\n", id, st, own, title }
  ' "$TICKETS"
}

mtime() { stat -f %m "$TICKETS" 2>/dev/null || stat -c %Y "$TICKETS"; }

cycle=0
while true; do
  cycle=$((cycle + 1))
  before="$(mtime)"

  run_agent implementer "$SOURCE_DIR" \
    "Read the ticket file at $TICKETS and follow the role instructions at $AGENTS/IMPLEMENTER_AGENT.md exactly for this cycle. Act only on tickets you own, then stop."
  run_agent tester "$REPO" \
    "Read the ticket file at $TICKETS and follow the role instructions at $AGENTS/TESTER_AGENT.md exactly for this cycle. First act on tickets you own. Then advance the standing task in $AGENTS/TESTER_TASK.md by one step, filing tickets for anything you hit. Then stop." \
    "${TESTER_FLAGS[@]}"

  { echo "--- $(ts) cycle $cycle tickets ---"; status_board; } | tee -a "$LOGS/loop.log"

  if [ "$MAX_CYCLES" -gt 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ]; then
    echo "Reached MAX_CYCLES=$MAX_CYCLES, exiting." | tee -a "$LOGS/loop.log"
    break
  fi

  if [ "$(mtime)" != "$before" ]; then
    echo "tickets changed this cycle, starting next cycle now" | tee -a "$LOGS/loop.log"
  else
    echo "idle, sleeping ${SLEEP_SECS}s" | tee -a "$LOGS/loop.log"
    sleep "$SLEEP_SECS"
  fi
done
