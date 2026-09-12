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
#   ./run-regression.sh smoke my-suite.md    # override the suite file for just that level
#   MODEL=sonnet ./run-regression.sh         # MODEL defaults to opus
#   DW_URL=... DW_TOKEN=... ./run-regression.sh
#   tail -f logs/regression.log              # watch from another terminal
#
# A suite-file override gets its own workspace derived from its filename
# (stripping a leading "regression-suite-" and trailing ".md"), never the
# level's canonical workspace — so a one-off custom suite can't delete
# fixtures the real smoke/complete/model-specific suite depends on.
#
# regression-suite-*.md is a second channel the implementer and tester write
# to directly (see their role prompts' "Adding a case" step), not just this
# script — so before AND after each level's run, this script commits any
# pending changes to those files, whoever made them.
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

case "$MODEL" in
  opus)   CO_AUTHOR="Claude Opus 5" ;;
  sonnet) CO_AUTHOR="Claude Sonnet 5" ;;
  haiku)  CO_AUTHOR="Claude Haiku 4.5" ;;
  *)      CO_AUTHOR="Claude ($MODEL)" ;;
esac

LEVEL="${1:-smoke}"
SUITE_OVERRIDE="${2:-}"

# Each entry is "level:override-or-empty". `complete` also runs `smoke`
# first (smoke is a prerequisite, per every suite file's own header); the
# override, if given, applies only to the level named on the command line,
# never to a prerequisite pulled in alongside it.
case "$LEVEL" in
  smoke)          RUN_SPECS=("smoke:$SUITE_OVERRIDE") ;;
  complete)       RUN_SPECS=("smoke:" "complete:$SUITE_OVERRIDE") ;;
  model-specific) RUN_SPECS=("model-specific:$SUITE_OVERRIDE") ;;
  all)
    [ -n "$SUITE_OVERRIDE" ] && { echo "a suite-file override is ambiguous with level 'all' — run one level at a time to override its file" >&2; exit 1; }
    RUN_SPECS=("smoke:" "complete:" "model-specific:")
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

default_suite_file() {
  case "$1" in
    smoke)          echo "regression-suite-smoke.md" ;;
    complete)       echo "regression-suite-complete.md" ;;
    model-specific) echo "regression-suite-model-specific.md" ;;
  esac
}

# Derives a workspace name from a suite file's basename so an override file
# never shares a workspace (and thus a Fixtures list) with the canonical
# suite for that level.
workspace_for_suite_file() {
  local base; base="$(basename "$1" .md)"
  case "$base" in
    regression-suite-*) echo "regression-${base#regression-suite-}" ;;
    *)                  echo "regression-$base" ;;
  esac
}

# Commits any pending changes to the suite files, from any source (the
# implementer/tester adding a case between runs, or this script's own run
# just now). Safe to call repeatedly — a no-op when nothing is dirty.
commit_suite_changes() {
  local msg="$1"
  ( cd "$REPO" && git diff --quiet -- "regression-suite-*.md" \
      && [ -z "$(git ls-files --others --exclude-standard -- "regression-suite-*.md")" ] ) && return 0
  git -C "$REPO" add "regression-suite-*.md"
  git -C "$REPO" commit -q -m "$msg" -m "Co-Authored-By: $CO_AUTHOR <noreply@anthropic.com>"
  echo "$msg" | tee -a "$LOGS/loop.log"
}

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
  local level="$1" suite_arg="$2" suite_file workspace

  if [ -n "$suite_arg" ]; then
    case "$suite_arg" in
      /*) suite_file="$suite_arg" ;;
      *)  suite_file="$REPO/$suite_arg" ;;
    esac
  else
    suite_file="$REPO/$(default_suite_file "$level")"
  fi
  [ -f "$suite_file" ] || { echo "suite file not found: $suite_file" >&2; exit 1; }
  workspace="$(workspace_for_suite_file "$suite_file")"

  if ! grep -q '^### ' "$suite_file"; then
    echo "$(ts) $level: $(basename "$suite_file") has no cases yet, skipping" | tee -a "$LOGS/loop.log"
    return 0
  fi

  echo "=== $(ts) regression run ($MODEL, level=$level, suite=$suite_file, workspace=$workspace) ===" | tee -a "$LOGS/loop.log"

  (cd "$REPO" && claude -p \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to file/comment on them. Follow the role instructions at $AGENTS/REGRESSION_AGENT.md exactly for this run, with these overrides: suite file is $suite_file; level is '$level'; workspace is $workspace. Read the suite file, exercise every case in it against the $workspace workspace, file or comment on issues for failures and performance regressions, then update the suite file with what you observed. Then stop." \
    --model "$MODEL" --dangerously-skip-permissions "${REGRESSION_FLAGS[@]}" 2>&1) \
    | tee -a "$LOGS/regression.log" \
    | sed -u "s/^/[regression:$level] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[regression:$level] run failed" | tee -a "$LOGS/loop.log"

  commit_suite_changes "regression: update $level suite from $(ts) run"
}

commit_suite_changes "regression: capture suite edits made outside a regression run"

for spec in "${RUN_SPECS[@]}"; do
  run_level "${spec%%:*}" "${spec#*:}"
done
