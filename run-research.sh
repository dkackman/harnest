#!/usr/bin/env bash
# Runs the researcher agent once per open "idea" issue awaiting research.
# Standalone — not part of the implementer/tester alternation in
# run-loop.sh, same category as run-regression.sh.
#
#   ./run-research.sh                       # research every open idea awaiting research
#   RESEARCH_MODEL=opus ./run-research.sh   # this agent only; defaults to sonnet
#   RESEARCH_EFFORT=high ./run-research.sh   # --effort; defaults medium
#   PROVIDER=ollama RESEARCH_MODEL=qwen2.5:32b ./run-research.sh
#   DW_URL=... DW_TOKEN=... ./run-research.sh
#   tail -f logs/research.log               # watch from another terminal
#
# Model/provider resolution lives in providers.sh. RESEARCH_MODEL defaults
# to "sonnet": deep feasibility judgment is
# expected to land with the implementer pass (and, where parked, with Don)
# — the research pass itself is triage-weight, so it gets the cheaper
# default while staying overridable like every other role.
#
# Unlike run-regression.sh's "one session per level," this driver gives
# each *issue* its own fresh claude -p session: the whole point is that
# issue #10's session never carries the context cost of issues #1-9, since
# nothing about a prior issue's research is relevant to the next one. All
# state that needs to survive between issues already lives on GitHub.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"   # the agents' clone (see run-loop.sh)
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
TICKET_OWNER="${TICKET_OWNER:-dkackman}"
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
PROVIDER="${PROVIDER:-anthropic}"
RESEARCH_MODEL="${RESEARCH_MODEL:-sonnet}"        # see header
RESEARCH_PROVIDER="${RESEARCH_PROVIDER:-$PROVIDER}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"
# Per-session cap (0 = none) and autocompact point, as in run-loop.sh. The
# 11 logged research sessions ran $0.68 median, $1.05 max.
RESEARCH_BUDGET_USD="${RESEARCH_BUDGET_USD:-3}"
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"
DW_URL="${DW_URL:-http://lem:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"

[ -d "$SOURCE_DIR" ] || { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"

. "$REPO/providers.sh"

RESEARCH_EFFORT="${RESEARCH_EFFORT:-$EFFORT}"   # --effort; medium unless set

resolve_model_env "$RESEARCH_PROVIDER" "$RESEARCH_MODEL" || exit 1
effort_flags anthropic "$RESEARCH_EFFORT" >/dev/null || exit 1
EFFORT_FLAGS=(); read -r -a EFFORT_FLAGS <<<"$(effort_flags "$RESEARCH_PROVIDER" "$RESEARCH_EFFORT")"
fb_words="$(fallback_model_flags "$RESEARCH_PROVIDER" "$FALLBACK_MODEL")" || exit 1
FALLBACK_FLAGS=(); [ -z "$fb_words" ] || read -r -a FALLBACK_FLAGS <<<"$fb_words"

LIMIT_FLAGS=(--autocompact "$AUTOCOMPACT_TOKENS")
[ "$RESEARCH_BUDGET_USD" = 0 ] || LIMIT_FLAGS+=(--max-budget-usd "$RESEARCH_BUDGET_USD")
# No driver lock: research makes read-only MCP calls and never deploys, so
# it is safe beside run-loop.sh or run-regression.sh. Its own session file
# keeps the rate-limit / died-session checks from reading another driver's.
LAST_SESSION="$LOGS/.last-session.research"

ts() { date '+%H:%M:%S'; }

RESEARCH_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  "${ISOLATION_FLAGS[@]}"
  --tools "$RESEARCHER_TOOLS"
  "${RESEARCHER_PERMISSION_FLAGS[@]}"
)

# run_session <issue_number>
# One `claude -p` invocation of the researcher agent, scoped to exactly one
# issue, run from SOURCE_DIR (Read/Grep/git need real paths against the
# checkout — same cwd the implementer uses, but read-only).
run_session() {
  local n="$1" attempt
  # Same rate-limit sleep and one retry of a died session as the other
  # drivers (providers.sh); without them a rejected window ran every idea
  # as a $0 no-op session.
  for attempt in 1 2; do
  : > "$LAST_SESSION"
  (cd "$SOURCE_DIR" && env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} claude -p \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER. Your role instructions are in your system prompt (the contents of $AGENTS/RESEARCHER.agent.md); follow them exactly for this run, researching and dispositioning ONLY issue #$n. The harness repo's CLAUDE.md (for its 'Ticket protocol' section) is at $REPO/CLAUDE.md. Then stop.

$(runtime_note researcher "$RESEARCH_PROVIDER" "$RESEARCH_MODEL")" \
    --model "$RESEARCH_MODEL" ${FALLBACK_FLAGS[@]+"${FALLBACK_FLAGS[@]}"} ${EFFORT_FLAGS[@]+"${EFFORT_FLAGS[@]}"} "${LIMIT_FLAGS[@]}" \
    --append-system-prompt-file "$AGENTS/RESEARCHER.agent.md" \
    "${STREAM_FLAGS[@]}" "${RESEARCH_FLAGS[@]}" 2>&1 < /dev/null | render_stream research) \
    | tee -a "$LOGS/research.log" "$LAST_SESSION" \
    | sed -u "s/^/[researcher:#$n] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[researcher:#$n] run failed" | tee -a "$LOGS/loop.log"
  sleep_if_rate_limited "$LAST_SESSION"
  session_died "$LAST_SESSION" || break
  [ "$attempt" -eq 1 ] || break
  echo "[researcher:#$n] session ended without a result; retrying once in ${SESSION_RETRY_PAUSE_SECS}s" | tee -a "$LOGS/loop.log"
  sleep "$SESSION_RETRY_PAUSE_SECS"
  done
}

park_external_issues

# idea + owner:researcher with no status:* label - the role prompt's own
# "still yours?" test, applied before a session is spent on it.
issues=()
while read -r n; do issues+=("$n"); done < <(
  gh issue list --repo "$TICKET_REPO" --state open --limit 200 \
    --label idea --label owner:researcher --json number,labels \
    --jq '.[] | select([.labels[].name | select(startswith("status:"))] | length == 0) | .number'
)

if [ "${#issues[@]}" -eq 0 ]; then
  echo "$(ts) no idea issues awaiting research" | tee -a "$LOGS/loop.log"
  exit 0
fi

echo "=== $(ts) research run ($MODEL_LABEL, ${#issues[@]} issue(s): ${issues[*]}) ===" | tee -a "$LOGS/loop.log"
for n in "${issues[@]}"; do
  echo "--- $(ts) researching #$n ---" | tee -a "$LOGS/loop.log"
  run_session "$n"
done
