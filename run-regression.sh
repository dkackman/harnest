#!/usr/bin/env bash
# Runs the regression agent once per requested level against the live dw MCP
# server. Standalone — not part of the implementer/tester alternation in
# run-loop.sh. Each level has its own suite file and workspace, so a run
# never mixes fixtures or timings across levels:
#   smoke           regression-suite-smoke.md           regression-smoke
#   complete        regression-suite-complete.md        regression-complete
#   model-specific  regression-suite-model-specific.md  regression-model-specific
#
#   ./run-regression.sh                      # smoke only (the default)
#   ./run-regression.sh complete             # smoke, then complete
#   ./run-regression.sh model-specific       # model-specific only
#   ./run-regression.sh all                  # smoke, complete, model-specific
#   ./run-regression.sh smoke my-suite.md    # override the suite file for one level
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

LEVEL="${1:-smoke}"
SUITE_OVERRIDE="${2:-}"

default_suite_file() {
  case "$1" in
    smoke)          echo "regression-suite-smoke.md" ;;
    complete)       echo "regression-suite-complete.md" ;;
    model-specific) echo "regression-suite-model-specific.md" ;;
    *) return 1 ;;
  esac
}

case "$LEVEL" in
  smoke|complete|model-specific)
    LEVELS_TO_RUN=("$LEVEL")
    ;;
  all)
    [ -n "$SUITE_OVERRIDE" ] && { echo "a suite-file override is ambiguous with level 'all' — run one level at a time to override its file" >&2; exit 1; }
    LEVELS_TO_RUN=(smoke complete model-specific)
    ;;
  *)
    echo "unknown level '$LEVEL' (expected: smoke, complete, model-specific, all)" >&2
    exit 1
    ;;
esac

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

run_level() {
  local level="$1" suite_arg="$2" suite_file workspace before_hash after_hash

  if [ -n "$suite_arg" ]; then
    case "$suite_arg" in
      /*) suite_file="$suite_arg" ;;
      *)  suite_file="$REPO/$suite_arg" ;;
    esac
  else
    suite_file="$REPO/$(default_suite_file "$level")"
  fi
  [ -f "$suite_file" ] || { echo "suite file not found: $suite_file" >&2; exit 1; }
  workspace="regression-$level"

  echo "=== $(ts) regression run ($MODEL, level=$level, suite=$suite_file, workspace=$workspace) ===" | tee -a "$LOGS/loop.log"

  before_hash="$(git -C "$REPO" hash-object "$suite_file" 2>/dev/null || true)"

  (cd "$REPO" && claude -p \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to file/comment on them. Follow the role instructions at $AGENTS/REGRESSION_AGENT.md exactly for this run, with these overrides: suite file is $suite_file; level is '$level'; workspace is $workspace. Read the suite file, exercise every case in it against the $workspace workspace, file or comment on issues for failures and performance regressions, then update the suite file with what you observed. Then stop." \
    --model "$MODEL" --dangerously-skip-permissions "${REGRESSION_FLAGS[@]}" 2>&1) \
    | tee -a "$LOGS/regression.log" \
    | sed -u "s/^/[regression:$level] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[regression:$level] run failed" | tee -a "$LOGS/loop.log"

  after_hash="$(git -C "$REPO" hash-object "$suite_file" 2>/dev/null || true)"
  if [ -n "$before_hash" ] && [ "$before_hash" != "$after_hash" ]; then
    git -C "$REPO" add "$suite_file"
    git -C "$REPO" commit -q -m "regression: update $level suite from $(ts) run" \
      -m "$(printf 'Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')"
    echo "$(basename "$suite_file") updated and committed" | tee -a "$LOGS/loop.log"
  fi
}

for level in "${LEVELS_TO_RUN[@]}"; do
  run_level "$level" "$SUITE_OVERRIDE"
done
