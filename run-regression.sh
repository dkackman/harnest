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
#   REGRESSION_MODEL=opus ./run-regression.sh   # this agent only; defaults to MODEL
#   PROVIDER=ollama MODEL=qwen2.5:32b ./run-regression.sh   # a non-Anthropic model
#   DW_URL=... DW_TOKEN=... ./run-regression.sh
#   tail -f logs/regression.log              # watch from another terminal
#
# Model/provider resolution lives in providers.sh — see its header for the
# supported providers and the per-provider knobs (OLLAMA_*, GW_*).
#
# A suite-file override gets its own workspace derived from its filename
# (stripping a leading "regression-suite-" and trailing ".md"), never the
# level's canonical workspace — so a one-off custom suite can't delete
# fixtures the real smoke/complete/model-specific suite depends on.
#
# regression-suite-*.md is a second channel the tester writes to directly
# (see its role prompt's "Adding a case" step), not just this script.
# run-loop.sh commits the tester's edits under the tester's identity; as a
# fallback, before the first level runs, this script commits anything still
# dirty under a neutral "unknown origin" trailer, and after each level it
# commits that level's run under the regression model's own trailer.
#
# Run it by hand, from cron, or wrapped with the `loop` skill for a recurring
# cadence — it does not loop or sleep internally.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/diffusers-workflow}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
MODEL="${MODEL:-opus}"          # default model
PROVIDER="${PROVIDER:-anthropic}"  # where that model lives: anthropic|ollama|gateway
REGRESSION_MODEL="${REGRESSION_MODEL:-$MODEL}"
REGRESSION_PROVIDER="${REGRESSION_PROVIDER:-$PROVIDER}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"   # optional; passed as --fallback-model
DW_URL="${DW_URL:-http://192.168.1.194:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"
PLUGIN_DIR="$SOURCE_DIR/plugins/dw"

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

. "$REPO/providers.sh"

# Reject a bad model/provider (or fallback) before touching the ticket board
# or the workspace. FALLBACK_FLAGS is an array so a name like opus[1m] is
# never glob-expanded on the claude command line.
resolve_model_env "$REGRESSION_PROVIDER" "$REGRESSION_MODEL" || exit 1
fb_words="$(fallback_model_flags "$REGRESSION_PROVIDER" "$FALLBACK_MODEL")" || exit 1
FALLBACK_FLAGS=(); [ -z "$fb_words" ] || read -r -a FALLBACK_FLAGS <<<"$fb_words"

# The Co-Authored-By trailer on commits this script makes for its own run —
# the one durable record of which model edited the suite (see co_author_for).
co_author_for "$REGRESSION_PROVIDER" "$REGRESSION_MODEL"

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

# Same isolation as the tester in run-loop.sh: this repo has no MCP config of
# its own, so dw is handed explicitly and --strict-mcp-config keeps it the
# only server visible. --plugin-dir loads the dw plugin live from the source
# checkout so skill fixes are covered without a reinstall. The permission
# allowlist (providers.sh) is the same fence the tester runs behind.
REGRESSION_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  --plugin-dir "$PLUGIN_DIR"
  "${CONSUMER_PERMISSION_FLAGS[@]}"
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

  echo "=== $(ts) regression run ($MODEL_LABEL, level=$level, suite=$suite_file, workspace=$workspace) ===" | tee -a "$LOGS/loop.log"

  (cd "$REPO" && env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} claude -p \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to file/comment on them. Follow the role instructions at $AGENTS/REGRESSION_AGENT.md exactly for this run, with these overrides: suite file is $suite_file; level is '$level'; workspace is $workspace. Read the suite file, exercise every case in it against the $workspace workspace, file or comment on issues for failures and performance regressions, then update the suite file with what you observed. Then stop.

$(runtime_note regression "$REGRESSION_PROVIDER" "$REGRESSION_MODEL")" \
    --model "$REGRESSION_MODEL" ${FALLBACK_FLAGS[@]+"${FALLBACK_FLAGS[@]}"} \
    "${REGRESSION_FLAGS[@]}" 2>&1) \
    | tee -a "$LOGS/regression.log" \
    | sed -u "s/^/[regression:$level] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[regression:$level] run failed" | tee -a "$LOGS/loop.log"

  commit_suite_changes "regression: update $level suite from $(ts) run ($MODEL_LABEL)"
}

# Fallback only: run-loop.sh commits the tester's own suite edits under the
# tester's identity, so anything still dirty here is of unknown origin (a
# hand edit between runs, or a cycle that died before committing). It is
# committed so this run's commit stays attributable to this run — but under a
# neutral name, never the regression model, which didn't write it.
commit_suite_changes "regression: capture suite edits of unknown origin made outside a regression run" \
  "unknown (edited outside a regression run)" "noreply@localhost"

for spec in "${RUN_SPECS[@]}"; do
  run_level "${spec%%:*}" "${spec#*:}"
done
