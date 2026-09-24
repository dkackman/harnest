#!/usr/bin/env bash
# Runs the feature lead's read-only sessions (roadmap R11): one fresh session
# per feature issue that is the lead's turn to design, or to decompose into
# stages. Standalone, like run-research.sh: no driver lock, because these
# sessions never change code, deploy, or run anything on the GPU.
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
# Which sessions run here:
#   design     feature + owner:lead, not a stage, no status:plan-approved and
#              no wontfix: the first plan, a revision after Don's answers,
#              or recording his decline
#   decompose  feature + owner:lead + status:plan-approved, not a stage, and no
#              comment carrying <!-- harnest:decomposed --> yet: file (or finish
#              filing) the stages, hand the parent to the tester
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
LEAD_MODEL="${LEAD_MODEL:-claude-opus-5-5}"
LEAD_PROVIDER="${LEAD_PROVIDER:-$PROVIDER}"
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
effort_flags anthropic "$LEAD_EFFORT" >/dev/null || exit 1
EFFORT_FLAGS=(); read -r -a EFFORT_FLAGS <<<"$(effort_flags "$LEAD_PROVIDER" "$LEAD_EFFORT")"
fb_words="$(fallback_model_flags "$LEAD_PROVIDER" "$FALLBACK_MODEL")" || exit 1
FALLBACK_FLAGS=(); [ -z "$fb_words" ] || read -r -a FALLBACK_FLAGS <<<"$fb_words"

LAST_SESSION="$LOGS/.last-session.features"
ts() { date '+%H:%M:%S'; }

LEAD_DESIGN_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  "${ISOLATION_FLAGS[@]}"
  --tools "$LEAD_DESIGN_TOOLS"
  "${LEAD_DESIGN_PERMISSION_FLAGS[@]}"
)

# only_filter: keep the numbers ONLY_ISSUES names, when it is set.
only_filter() {
  if [ -z "$ONLY_ISSUES" ]; then cat; return; fi
  local pat
  pat="$(printf '%s' "$ONLY_ISSUES" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//;s/ /|/g')"
  grep -E "^($pat)$" || true
}

# feature_queue <design|decompose>: issue numbers, ascending.
feature_queue() {
  local filter
  case "$1" in
    design)    filter='(.labels | map(.name)) as $l | ($l | index("stage")) == null and ($l | index("status:plan-approved")) == null and ($l | index("wontfix")) == null' ;;
    # Approved and not yet marked decomposed. The marker is on the
    # decompose hand-off comment, so a session cut off after filing some
    # stages comes back here and resumes, rather than stranding the parent
    # with a partial stage list that no queue matches.
    decompose) filter='(.labels | map(.name)) as $l | ($l | index("stage")) == null and ($l | index("status:plan-approved")) != null and ($l | index("wontfix")) == null and ([.comments[].body | select(contains("<!-- harnest:decomposed -->"))] | length) == 0' ;;
  esac
  gh issue list --repo "$TICKET_REPO" --state open --limit 200 --label feature --label owner:lead \
    --json number,labels,comments --jq ".[] | select($filter) | .number" | sort -n | only_filter
}

# run_session <n> <kind> <budget> <instructions>
run_session() {
  local n="$1" kind="$2" budget="$3" instructions="$4" tag attempt prompt_file
  tag="lead:#$n"; [ "$kind" = design ] || tag="lead:#$n $kind"
  prompt_file="$(role_prompt lead "$kind" "$LOGS/.prompt.lead.md")" || return 0
  local -a limits=(--autocompact "$AUTOCOMPACT_TOKENS")
  [ "$budget" = 0 ] || limits+=(--max-budget-usd "$budget")
  local plan
  plan="$(plan_text "$n")"
  for attempt in 1 2; do
    : > "$LAST_SESSION"
    echo "=== $(ts) $tag ($MODEL_LABEL)$([ "$attempt" -gt 1 ] && echo " retry") ===" | tee -a "$LOGS/loop.log"
    (cd "$LEAD_TREE" && env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} claude -p \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER. $instructions Your working directory is a detached worktree of the diffusers-workflow source at origin/develop ($(git -C "$LEAD_TREE" rev-parse --short HEAD)); read it, never edit it. Then stop.

The issue as of $(ts) — start from this rather than fetching it; gh is for acting on it and for anything newer:

$(issue_context "$n")
$([ -n "$plan" ] && printf '\n## The current plan, in full (comment headed <!-- harnest:plan -->)\n\n%s\n' "$plan")

$(runtime_note lead "$LEAD_PROVIDER" "$LEAD_MODEL")" \
      --model "$LEAD_MODEL" ${FALLBACK_FLAGS[@]+"${FALLBACK_FLAGS[@]}"} ${EFFORT_FLAGS[@]+"${EFFORT_FLAGS[@]}"} "${limits[@]}" \
      --append-system-prompt-file "$prompt_file" \
      "${STREAM_FLAGS[@]}" "${LEAD_DESIGN_FLAGS[@]}" 2>&1 < /dev/null | render_stream lead) \
      | tee -a "$LOGS/lead.log" "$LAST_SESSION" \
      | sed -u "s/^/[$tag] /" \
      | tee -a "$LOGS/loop.log" \
      || echo "[$tag] run failed" | tee -a "$LOGS/loop.log"
    sleep_if_rate_limited "$LAST_SESSION"
    session_died "$LAST_SESSION" || break
    [ "$attempt" -eq 1 ] || break
    echo "[$tag] session ended without a result; retrying once in ${SESSION_RETRY_PAUSE_SECS}s" | tee -a "$LOGS/loop.log"
    sleep "$SESSION_RETRY_PAUSE_SECS"
  done
  audit_issue "$n" lead
}

park_external_issues
refresh_plugin_tree "$SOURCE_DIR" "$LEAD_TREE" >/dev/null \
  || { echo "could not create/refresh the lead worktree $LEAD_TREE from $SOURCE_DIR" >&2; exit 1; }

design=(); decompose=()
while read -r n; do [ -n "$n" ] && design+=("$n"); done < <(feature_queue design)
while read -r n; do [ -n "$n" ] && decompose+=("$n"); done < <(feature_queue decompose)
if [ "${#design[@]}" -eq 0 ] && [ "${#decompose[@]}" -eq 0 ]; then
  echo "$(ts) [lead] no feature waiting on a design or a decomposition" | tee -a "$LOGS/loop.log"
  exit 0
fi

echo "=== $(ts) feature run ($MODEL_LABEL): design ${design[*]:-none}; decompose ${decompose[*]:-none} ===" | tee -a "$LOGS/loop.log"
for n in ${design[@]+"${design[@]}"}; do
  run_session "$n" design "$LEAD_DESIGN_BUDGET_USD" \
    "This is a DESIGN session for feature issue #$n only: your role instructions for it are in your system prompt."
done
for n in ${decompose[@]+"${decompose[@]}"}; do
  run_session "$n" decompose "$LEAD_DECOMPOSE_BUDGET_USD" \
    "This is a DECOMPOSE session for feature issue #$n only: Don approved its plan; your role instructions for it are in your system prompt."
done
