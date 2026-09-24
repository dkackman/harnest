#!/usr/bin/env bash
# Runs the feature lead's read-only sessions (roadmap R11): one fresh session
# per feature or idea issue that is the lead's turn to design, or to
# decompose into stages. Standalone: no driver lock, because these sessions
# never change code, deploy, or run anything on the GPU.
#
#   ./run-features.sh                       # every feature waiting on the lead
#   ONLY_ISSUES=378 ./run-features.sh       # just these
#   LEAD_MODEL=claude-opus-5-5 LEAD_EFFORT=high ./run-features.sh
#   tail -f logs/loop.log                   # prefixed [lead:#378] / [lead:#378 decompose]
#
# The rest of a feature runs in run-loop.sh, under its lock:
#   - build sessions (a stage whose blockers are closed);
#   - close-outs (declined, or every stage closed);
#   - the tester's spec and verify sessions.
# Builds deploy to lem and must be serial with the implementer's deploys.
# A close-out commits to develop in the shared checkout. run-loop holds the
# lock for its whole life, so work that needs the lock can't live here.
#
# Which sessions run here (queues lead:design and lead:decompose of
# lib/classify.jq, which holds the rules):
#   design     a feature or idea with owner:lead and no approved plan: the
#              first plan, a revision after Don's answers, recording his
#              decline; or an approved plan the tester's spec questions
#              sent back
#   decompose  an approved plan whose current version has no decomposed
#              marker yet (first time, a re-plan, or a cut-off session)
#
# The lead reads source from its own detached worktree at origin/develop
# (LEAD_TREE, reset before every run), never from SOURCE_DIR. SOURCE_DIR is on
# whatever branch the last build left checked out, and a design must read
# what's actually on develop.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"
LEAD_TREE="${LEAD_TREE:-$HOME/src/dkackman/dw-agent-lead}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
TICKET_OWNER="${TICKET_OWNER:-dkackman}"
LOGS="$REPO/logs"
ONLY_ISSUES="${ONLY_ISSUES:-}"
PROVIDER="${PROVIDER:-anthropic}"
# A wrong plan is the costliest error in the feature flow and the least
# likely to be caught (the tester writes its cases from the plan), so the
# lead runs on the tester's strong model by default. Exact id, not an alias.
LEAD_MODEL="${LEAD_MODEL:-${TESTER_MODEL:-claude-opus-5-5}}"
LEAD_PROVIDER="${LEAD_PROVIDER:-${TESTER_PROVIDER:-$PROVIDER}}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"
# Per-session caps (0 = none). A design reads the proposal, runs one Explore
# sweep and writes one plan. The first hand-run design (#378) sized these.
LEAD_DESIGN_BUDGET_USD="${LEAD_DESIGN_BUDGET_USD:-6}"
LEAD_DECOMPOSE_BUDGET_USD="${LEAD_DECOMPOSE_BUDGET_USD:-4}"
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

LEAD_EFFORT="${LEAD_EFFORT:-$EFFORT}"
resolve_model_env "$LEAD_PROVIDER" "$LEAD_MODEL" || exit 1
# Validate the effort and fallback now, not three minutes in.
session_flags "$LEAD_PROVIDER" "$LEAD_MODEL" "$LEAD_EFFORT" 0 || exit 1

LAST_SESSION="$LOGS/.last-session.features"
ts() { date '+%H:%M:%S'; }

LEAD_DESIGN_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  "${ISOLATION_FLAGS[@]}"
  --tools "$LEAD_DESIGN_TOOLS"
  "${LEAD_DESIGN_PERMISSION_FLAGS[@]}"
)

# run_session <n> <kind> <budget> <instructions>
run_session() {
  local n="$1" kind="$2" budget="$3" instructions="$4" tag prompt_file before plan
  tag="lead:#$n"; [ "$kind" = design ] || tag="lead:#$n $kind"
  prompt_file="$(role_prompt lead "$kind" "$LOGS/.prompt.lead.$kind.md")" || return 0
  session_flags "$LEAD_PROVIDER" "$LEAD_MODEL" "$LEAD_EFFORT" "$budget" || return 0
  plan="$(plan_text "$n")"
  before="$(issue_fingerprint "$TICKET_REPO" "$n")"
  run_claude_session "$tag" lead "$LEAD_TREE" "$prompt_file" \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER. $instructions Your working directory is a detached worktree of the diffusers-workflow source at origin/develop ($(git -C "$LEAD_TREE" rev-parse --short HEAD)); read it, never edit it. Then stop.

The issue as of $(ts) — start from this rather than fetching it; gh is for acting on it and for anything newer:

$(issue_context "$n")
$([ -n "$plan" ] && printf '\n## The current plan, in full (comment headed <!-- harnest:plan -->)\n\n%s\n' "$plan")

$(runtime_note lead "$LEAD_PROVIDER" "$LEAD_MODEL")" \
    "${SESSION_FLAGS[@]}" "${LEAD_DESIGN_FLAGS[@]}"
  audit_issue "$n" lead
  session_ran "$LAST_SESSION" && note_progress "$TICKET_REPO" "$n" "$before" "$tag" "lead:$kind"
  return 0
}

# main: in a function, and called with `exit` on the same line, so bash has
# parsed all of it before it runs, and editing this file mid-run can't make
# bash resume at a stale byte offset. An edit takes effect at the next start.
main() {
park_external_issues
refresh_plugin_tree "$SOURCE_DIR" "$LEAD_TREE" >/dev/null \
  || { echo "could not create/refresh the lead worktree $LEAD_TREE from $SOURCE_DIR" >&2; exit 1; }

design=(); decompose=()
# Each entry is "<number><tab><the classifier's reason>".
while IFS=$'\t' read -r n _ reason; do [ -n "$n" ] && design+=("$n"$'\t'"$reason"); done < <(queue_issues lead:design)
while IFS=$'\t' read -r n _ reason; do [ -n "$n" ] && decompose+=("$n"$'\t'"$reason"); done < <(queue_issues lead:decompose)
if [ "${#design[@]}" -eq 0 ] && [ "${#decompose[@]}" -eq 0 ]; then
  echo "$(ts) [lead] no feature waiting on a design or a decomposition" | tee -a "$LOGS/loop.log"
  exit 0
fi

echo "=== $(ts) feature run ($MODEL_LABEL): design $(printf '%s ' ${design[@]+"${design[@]%%$'\t'*}"}); decompose $(printf '%s ' ${decompose[@]+"${decompose[@]%%$'\t'*}"}) ===" | tee -a "$LOGS/loop.log"
local entry
for entry in ${design[@]+"${design[@]}"}; do
  run_session "${entry%%$'\t'*}" design "$LEAD_DESIGN_BUDGET_USD" \
    "This is a DESIGN session for issue #${entry%%$'\t'*} only: your role instructions for it are in your system prompt. The driver selected it because: ${entry#*$'\t'}."
done
for entry in ${decompose[@]+"${decompose[@]}"}; do
  run_session "${entry%%$'\t'*}" decompose "$LEAD_DECOMPOSE_BUDGET_USD" \
    "This is a DECOMPOSE session for feature issue #${entry%%$'\t'*} only: Don approved its plan; your role instructions for it are in your system prompt. The driver selected it because: ${entry#*$'\t'}."
done
}

main "$@"; exit
