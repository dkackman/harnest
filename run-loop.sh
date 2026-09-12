#!/usr/bin/env bash
# Drives the implementer and tester Claude Code agents in strictly alternating
# cycles. Both agents communicate only through GitHub Issues on TICKET_REPO.
#
#   ./run-loop.sh                       # run forever
#   MAX_CYCLES=3 SLEEP_SECS=60 ./run-loop.sh
#   MODEL=sonnet ./run-loop.sh          # default is opus, for every agent
#   TESTER_MODEL=opus IMPLEMENTER_MODEL=haiku ./run-loop.sh
#                                       # per-role models; each defaults to MODEL
#   PROVIDER=ollama MODEL=gemma4:31b-it-q4_K_M ./run-loop.sh
#                                       # a non-Anthropic model, served by Ollama
#   DW_URL=... DW_TOKEN=... ./run-loop.sh   # dw MCP endpoint handed to the tester
#   tail -f logs/loop.log               # watch from another terminal
#
# Model/provider resolution lives in providers.sh — see its header for the
# supported providers and the per-provider knobs (OLLAMA_*, GW_*).
#
# The implementer runs inside the diffusers-workflow source checkout; the tester
# runs inside this repo, which contains no code. That working-directory split is
# what keeps the tester a pure MCP consumer. Ticket state (pre-2026-09-12) lived
# in mcp-feedback.md / mcp-feedback-archive.md here; both are frozen history now
# that tickets are GitHub Issues on TICKET_REPO.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/diffusers-workflow}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
SLEEP_SECS="${SLEEP_SECS:-120}"
MAX_CYCLES="${MAX_CYCLES:-0}"   # 0 = run forever
MODEL="${MODEL:-opus}"          # default model, for any role without its own
PROVIDER="${PROVIDER:-anthropic}"  # where that model lives: anthropic|ollama|gateway
# Per-role overrides. Both roles default to MODEL/PROVIDER, so the original
# single-knob behavior is unchanged; splitting them is how you run, say, a
# cheap model on the implementer while the tester stays on a strong one.
IMPLEMENTER_MODEL="${IMPLEMENTER_MODEL:-$MODEL}"
TESTER_MODEL="${TESTER_MODEL:-$MODEL}"
IMPLEMENTER_PROVIDER="${IMPLEMENTER_PROVIDER:-$PROVIDER}"
TESTER_PROVIDER="${TESTER_PROVIDER:-$PROVIDER}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"   # optional; passed as --fallback-model
DW_URL="${DW_URL:-http://192.168.1.194:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"     # dev token; the server is LAN-only
PLUGIN_DIR="$SOURCE_DIR/plugins/dw"

[ -d "$SOURCE_DIR" ] || { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }
[ -d "$PLUGIN_DIR" ] || { echo "dw plugin source not found: $PLUGIN_DIR" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"

. "$REPO/providers.sh"

# Reject a bad model/provider (or a fallback the role's provider can't serve)
# before the first cycle rather than three minutes into it. This is the only
# guard: run_agent trusts these pairs and never aborts the loop over them.
resolve_model_env "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_MODEL" || exit 1
resolve_model_env "$TESTER_PROVIDER" "$TESTER_MODEL" || exit 1
validate_fallback_model "$IMPLEMENTER_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$TESTER_PROVIDER" "$FALLBACK_MODEL" || exit 1

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

# run_agent <name> <cwd> <provider> <model> <prompt> [extra claude flags...]
# Streams the agent's output to the terminal, its own log, and the combined log.
run_agent() {
  local name="$1" dir="$2" provider="$3" model="$4" prompt="$5"; shift 5

  # Both pairs were validated at startup, so these can't fail on a bad pair —
  # but a bare failing call in the while body would take the whole driver down
  # under set -e with no log line, so any failure is logged and skipped like a
  # failed cycle rather than propagated.
  local fb_words
  if ! resolve_model_env "$provider" "$model" \
     || ! fb_words="$(fallback_model_flags "$provider" "$FALLBACK_MODEL")"; then
    echo "[$name] cycle failed, continuing" | tee -a "$LOGS/loop.log"
    return 0
  fi
  # An array, so a fallback like opus[1m] is never glob-expanded.
  local -a fallback=()
  [ -z "$fb_words" ] || read -r -a fallback <<<"$fb_words"

  # Each agent is a fresh session, so its model is otherwise unrecorded: a
  # later reader can't tell an Opus verification from a 31B one. Say it in the
  # prompt, where the agent can carry it into the comments it writes.
  local note full_prompt
  note="$(runtime_note "$name" "$provider" "$model")"
  full_prompt="$prompt

$note"

  echo "=== $(ts) cycle $cycle: $name ($MODEL_LABEL) ===" | tee -a "$LOGS/loop.log"
  (cd "$dir" && env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} \
      claude -p "$full_prompt" \
      --model "$model" ${fallback[@]+"${fallback[@]}"} \
      --dangerously-skip-permissions "$@" 2>&1) \
    | tee -a "$LOGS/$name.log" \
    | sed -u "s/^/[$name] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[$name] cycle failed, continuing" | tee -a "$LOGS/loop.log"
}

# One line per open issue: #NN  status-labels  owner-label  title
status_board() {
  gh issue list --repo "$TICKET_REPO" --state open --limit 200 \
    --json number,title,labels \
    --jq '.[] | [
      ("#" + (.number|tostring)),
      (([.labels[].name | select(startswith("status:"))]) + ["open"])[0],
      (([.labels[].name | select(startswith("owner:"))]) + ["unowned"])[0],
      .title
    ] | @tsv' \
  | awk -F'\t' '{printf "  %-5s %-24s %-18s %s\n", $1, $2, $3, $4}'
}

cycle=0
while true; do
  cycle=$((cycle + 1))
  before="$(status_board)"

  run_agent implementer "$SOURCE_DIR" "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_MODEL" \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Follow the role instructions at $AGENTS/IMPLEMENTER_AGENT.md exactly for this cycle. Act only on issues you own (owner:implementer), then stop."
  run_agent tester "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Follow the role instructions at $AGENTS/TESTER_AGENT.md exactly for this cycle. First act on issues you own (owner:tester). Then advance the standing task in $AGENTS/TESTER_TASK.md by one step, filing tickets for anything you hit. Then stop." \
    "${TESTER_FLAGS[@]}"

  # The tester is the only agent in this loop that edits the regression suite
  # files (it adds a case once it has verified it over MCP; the implementer
  # only proposes one in a hand-off comment). Commit whatever it added this
  # cycle under its own identity, so the trailer names the model that wrote
  # the case. A no-op when the suite files are clean.
  co_author_for "$TESTER_PROVIDER" "$TESTER_MODEL"
  commit_suite_changes "regression: tester added case (cycle $cycle)" "$CO_AUTHOR" "$CO_AUTHOR_EMAIL" \
    || echo "[tester] suite commit failed, continuing" | tee -a "$LOGS/loop.log"

  { echo "--- $(ts) cycle $cycle tickets ---"; status_board; } | tee -a "$LOGS/loop.log"

  if [ "$MAX_CYCLES" -gt 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ]; then
    echo "Reached MAX_CYCLES=$MAX_CYCLES, exiting." | tee -a "$LOGS/loop.log"
    break
  fi

  if [ "$(status_board)" != "$before" ]; then
    echo "tickets changed this cycle, starting next cycle now" | tee -a "$LOGS/loop.log"
  else
    echo "idle, sleeping ${SLEEP_SECS}s" | tee -a "$LOGS/loop.log"
    sleep "$SLEEP_SECS"
  fi
done
