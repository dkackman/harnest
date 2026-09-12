#!/usr/bin/env bash
# Runs the regression agent once against the live dw MCP server. Standalone —
# not part of the implementer/tester alternation in run-loop.sh. The agent
# reads regression-suite.md, exercises every case in the regression-smoke
# workspace, files/comments on GitHub Issues for failures and performance
# regressions, and appends what it observed back into regression-suite.md.
#
#   ./run-regression.sh                      # one pass
#   MODEL=sonnet ./run-regression.sh         # MODEL defaults to opus
#   DW_URL=... DW_TOKEN=... ./run-regression.sh
#   tail -f logs/regression.log              # watch from another terminal
#
# Run it by hand, from cron, or wrapped with the `loop` skill for a recurring
# cadence — it does not loop or sleep internally.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/diffusers-workflow}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
MODEL="${MODEL:-opus}"
DW_URL="${DW_URL:-http://192.168.1.194:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"
PLUGIN_DIR="$SOURCE_DIR/plugins/dw"

[ -d "$PLUGIN_DIR" ] || { echo "dw plugin source not found: $PLUGIN_DIR" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"

ts() { date '+%H:%M:%S'; }

# Same isolation as the tester in run-loop.sh: this repo has no MCP config of
# its own, so dw is handed explicitly and --strict-mcp-config keeps it the
# only server visible. --plugin-dir loads the dw plugin live from the source
# checkout so skill fixes are covered without a reinstall.
REGRESSION_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  --plugin-dir "$PLUGIN_DIR"
)

echo "=== $(ts) regression run ($MODEL) ===" | tee -a "$LOGS/loop.log"

before_hash="$(git -C "$REPO" hash-object regression-suite.md 2>/dev/null || true)"

(cd "$REPO" && claude -p \
  "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to file/comment on them. Follow the role instructions at $AGENTS/REGRESSION_AGENT.md exactly for this run: read regression-suite.md, exercise every case in the regression-smoke workspace, file or comment on issues for failures and performance regressions, then update regression-suite.md with what you observed. Then stop." \
  --model "$MODEL" --dangerously-skip-permissions "${REGRESSION_FLAGS[@]}" 2>&1) \
  | tee -a "$LOGS/regression.log" \
  | sed -u "s/^/[regression] /" \
  | tee -a "$LOGS/loop.log" \
  || echo "[regression] run failed" | tee -a "$LOGS/loop.log"

after_hash="$(git -C "$REPO" hash-object regression-suite.md 2>/dev/null || true)"
if [ -n "$before_hash" ] && [ "$before_hash" != "$after_hash" ]; then
  git -C "$REPO" add regression-suite.md
  git -C "$REPO" commit -q -m "regression: update suite from $(ts) run" \
    -m "$(printf 'Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
  echo "regression-suite.md updated and committed" | tee -a "$LOGS/loop.log"
fi
