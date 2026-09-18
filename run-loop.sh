#!/usr/bin/env bash
# Drives the implementer and tester Claude Code agents in strictly alternating
# cycles. Both agents communicate only through GitHub Issues on TICKET_REPO.
#
#   ./run-loop.sh                       # run forever
#   MAX_CYCLES=3 SLEEP_SECS=60 ./run-loop.sh
#   IMPLEMENTER_MODEL=haiku TESTER_MODEL=opus ./run-loop.sh
#                                       # per-role models; defaults sonnet / opus
#   TRIAGE_MODEL=sonnet ./run-loop.sh   # triage session's model; defaults to TESTER_MODEL
#   PROVIDER=ollama IMPLEMENTER_MODEL=gemma4:31b-it-q4_K_M TESTER_MODEL=gemma4:31b-it-q4_K_M ./run-loop.sh
#                                       # a non-Anthropic model, served by Ollama
#   DW_URL=... DW_TOKEN=... ./run-loop.sh   # dw MCP endpoint handed to the tester
#   IMPLEMENTER_BUDGET_USD=8 TESTER_BUDGET_USD=5 TRIAGE_BUDGET_USD=3 ./run-loop.sh
#                                       # per-session --max-budget-usd caps (0 = none)
#   TESTER_TASK_EVERY=2 ./run-loop.sh   # standing task every Nth cycle
#   ONLY_ISSUES=227 ./run-loop.sh       # this cycle works #227 (and nothing
#                                       # else), implementer and tester both
#   tail -f logs/loop.log               # watch from another terminal
#
# Model/provider resolution lives in providers.sh — see its header for the
# supported providers and the per-provider knobs (OLLAMA_*, GW_*).
#
# The implementer runs inside the diffusers-workflow source checkout; the tester
# runs inside this repo, which contains no code. That working-directory split is
# what keeps the tester a pure MCP consumer. Tickets are GitHub Issues on
# TICKET_REPO; GitHub holds their full history, including what predates it.
#
# Sessions are per issue, not per role. One cycle is:
#   implementer triage   one session, only when 2+ issues are waiting: reads
#                        them all, closes duplicates, parks what needs parking,
#                        and leaves a `triage:` comment on each — including
#                        which issues to batch into one fix
#   implementer #N       one fresh session per remaining issue (a batch is
#                        worked by the first issue's session; the driver skips
#                        an issue that was handed off meanwhile)
#   tester #N            one fresh session per status:fixed-pending-verify issue
#   tester #N (handoff)  one fresh session per owner:tester issue with no
#                        status label - a suite/harness-file edit the
#                        implementer asked for but can't make itself
#   tester #N (answer)   one fresh session per owner:tester issue with
#                        status:needs-info - a question the implementer
#                        bounced back
#   tester task          one session, every TESTER_TASK_EVERY cycles: responds
#                        to wontfix/duplicate closures, then advances
#                        TESTER_TASK.agent.md one step
# Why: one 6-issue implementer session measured 269 turns at a 352k-token peak
# and 60M cached-input tokens — issue 6 paid to re-read issues 1-5 on every
# turn. A session's cost is context × turns, and per-issue sessions bound
# both. --max-budget-usd is the backstop for a session that runs away anyway;
# the role prompts tell each agent to leave a resumable trail (branch,
# progress comment) so a cut-off session is picked up, not lost.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/diffusers-workflow}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
TICKET_OWNER="${TICKET_OWNER:-dkackman}"   # GitHub login whose issues the agents may act on unasked
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
SLEEP_SECS="${SLEEP_SECS:-120}"
MAX_CYCLES="${MAX_CYCLES:-0}"   # 0 = run forever
# Comma-separated issue numbers. Set, it narrows *every* role's queue to those
# issues, so one cycle works them and nothing else — the way to drive a single
# issue through both agents without spending a session on each of the others.
# An issue the filter excludes is skipped silently rather than parked, and a
# queue of one skips triage by construction. Unset is the normal full run.
ONLY_ISSUES="${ONLY_ISSUES:-}"
PROVIDER="${PROVIDER:-anthropic}"  # where the models live: anthropic|ollama|gateway
# One model knob per role, no shared default: which role may run a weak model
# is a design decision, not a config detail. The tester defaults to opus —
# its independence is the point of the setup and a weak tester rubber-stamps
# silently. The implementer defaults to sonnet — its mistakes show up in the
# tester's verification, and it is the role that burns the most tokens. Under
# a non-anthropic PROVIDER both must be named (a Claude alias can't be served
# there; resolve_model_env rejects it at startup).
IMPLEMENTER_MODEL="${IMPLEMENTER_MODEL:-sonnet}"
TESTER_MODEL="${TESTER_MODEL:-opus}"
IMPLEMENTER_PROVIDER="${IMPLEMENTER_PROVIDER:-$PROVIDER}"
TESTER_PROVIDER="${TESTER_PROVIDER:-$PROVIDER}"
# Triage is the implementer's role but not its model by default: a wrong
# wontfix/duplicate/park call doesn't bounce back from the tester, it just
# disappears, and the session is short and capped, so the strong model is
# nearly free there. Follows the tester's model+provider unless set.
TRIAGE_MODEL="${TRIAGE_MODEL:-$TESTER_MODEL}"
TRIAGE_PROVIDER="${TRIAGE_PROVIDER:-$TESTER_PROVIDER}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"   # optional; passed as --fallback-model
# Per-session spend caps (--max-budget-usd; 0 = uncapped) and the context
# size at which a session auto-compacts instead of growing. Non-Anthropic
# providers report zero cost, so a cap never fires there.
IMPLEMENTER_BUDGET_USD="${IMPLEMENTER_BUDGET_USD:-8}"
TESTER_BUDGET_USD="${TESTER_BUDGET_USD:-5}"
TRIAGE_BUDGET_USD="${TRIAGE_BUDGET_USD:-3}"
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"
TESTER_TASK_EVERY="${TESTER_TASK_EVERY:-2}"   # standing task on every Nth cycle
DW_URL="${DW_URL:-http://lem:8765/mcp}"
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
resolve_model_env "$TRIAGE_PROVIDER" "$TRIAGE_MODEL" || exit 1
validate_fallback_model "$IMPLEMENTER_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$TESTER_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$TRIAGE_PROVIDER" "$FALLBACK_MODEL" || exit 1

ts() { date '+%H:%M:%S'; }

# Both agents get dw passed explicitly, and --strict-mcp-config makes it the
# *only* server they see. For the tester that's a necessity (its cwd has no
# MCP config); for the implementer it's a fence: the source checkout already
# has dw at local scope, but without --strict-mcp-config the session also
# inherits every account-level claude.ai connector (Gmail, Drive, Calendar),
# and an unattended agent has no business holding those. Tool schemas come from the server and are always fresh.
MCP_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
)
# --plugin-dir loads the dw plugin live from the implementer's working tree
# instead of the frozen copy in ~/.claude/plugins/cache, so skill fixes are
# testable without a reinstall. Only the tester needs it; the implementer
# works from the source tree itself.
TESTER_FLAGS=(
  "${MCP_FLAGS[@]}"
  --plugin-dir "$PLUGIN_DIR"
  "${CONSUMER_PERMISSION_FLAGS[@]}"
)
# The implementer's shell surface can't be enumerated without breaking a
# cycle the first time it needs sed or pip, so it runs under the auto-mode
# classifier instead: routine work is approved, destructive or exfiltrating
# actions are denied (a headless session never prompts; a denial comes back
# to the agent as a tool result and it routes around or stops).
IMPLEMENTER_FLAGS=(
  "${MCP_FLAGS[@]}"
  --permission-mode auto
)

# run_agent <role> <tag> <budget_usd> <cwd> <provider> <model> <prompt> [extra claude flags...]
# One fresh claude -p session. <role> picks the role prompt's runtime note
# and the per-role log file; <tag> (e.g. "#145", "triage", "task") is what
# distinguishes the sessions of one cycle in loop.log. Streams the agent's
# output to the terminal, its own log, and the combined log.
run_agent() {
  local role="$1" tag="$2" budget="$3" dir="$4" provider="$5" model="$6" prompt="$7"; shift 7
  local label="$role:$tag"

  # Both pairs were validated at startup, so these can't fail on a bad pair —
  # but a bare failing call in the while body would take the whole driver down
  # under set -e with no log line, so any failure is logged and skipped like a
  # failed session rather than propagated.
  local fb_words
  if ! resolve_model_env "$provider" "$model" \
     || ! fb_words="$(fallback_model_flags "$provider" "$FALLBACK_MODEL")"; then
    echo "[$label] session failed, continuing" | tee -a "$LOGS/loop.log"
    return 0
  fi
  # An array, so a fallback like opus[1m] is never glob-expanded.
  local -a fallback=()
  [ -z "$fb_words" ] || read -r -a fallback <<<"$fb_words"
  local -a limits=(--autocompact "$AUTOCOMPACT_TOKENS")
  [ "$budget" = 0 ] || limits+=(--max-budget-usd "$budget")

  # Each agent is a fresh session, so its model is otherwise unrecorded: a
  # later reader can't tell an Opus verification from a 31B one. Say it in the
  # prompt, where the agent can carry it into the comments it writes.
  local note full_prompt
  note="$(runtime_note "$role" "$provider" "$model")"
  full_prompt="$prompt

$note"

  echo "=== $(ts) cycle $cycle: $label ($MODEL_LABEL) ===" | tee -a "$LOGS/loop.log"
  (cd "$dir" && env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} \
      claude -p "$full_prompt" \
      --model "$model" ${fallback[@]+"${fallback[@]}"} "${limits[@]}" \
      "${STREAM_FLAGS[@]}" "$@" 2>&1 < /dev/null | render_stream "$role") \
    | tee -a "$LOGS/$role.log" \
    | sed -u "s/^/[$label] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[$label] session failed, continuing" | tee -a "$LOGS/loop.log"
}

# open_issues <owner-label> <fresh|verify|needsinfo>
# Issue numbers, ascending, of open issues carrying <owner-label> that are
# ready for that role: `fresh` = no status:* label at all (the implementer's
# work queue, and the tester's handoff queue), `verify` =
# status:fixed-pending-verify (the tester's), `needsinfo` =
# status:needs-info (a question bounced to whoever holds the owner label -
# the implementer bounces to owner:tester per IMPLEMENTER.agent.md step 5).
open_issues() {
  local owner="$1" mode="$2" filter
  case "$mode" in
    fresh)     filter='([.labels[].name | select(startswith("status:"))] | length) == 0' ;;
    verify)    filter='[.labels[].name] | index("status:fixed-pending-verify") != null' ;;
    needsinfo) filter='[.labels[].name] | index("status:needs-info") != null' ;;
    *) echo "open_issues: bad mode $mode" >&2; return 1 ;;
  esac
  local out
  out="$(gh issue list --repo "$TICKET_REPO" --state open --label "$owner" --limit 200 \
    --json number,labels --jq ".[] | select($filter) | .number" | sort -n)"
  if [ -n "$ONLY_ISSUES" ]; then
    local pat
    pat="$(printf '%s' "$ONLY_ISSUES" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//;s/ /|/g')"
    out="$(printf '%s\n' "$out" | grep -E "^($pat)$" || true)"
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
}

# still_ready <n> <owner-label> <fresh|verify|needsinfo>
# Re-check one issue just before its session starts: a triage session or an
# earlier per-issue session (working a batch) may have handed it off already.
still_ready() {
  local n="$1" owner="$2" mode="$3"
  open_issues "$owner" "$mode" | grep -qx "$n"
}

# implementer_pass — triage (when 2+ issues wait), then one session per issue.
implementer_pass() {
  local -a queue=()
  local n
  while IFS= read -r n; do [ -n "$n" ] && queue+=("$n"); done < <(open_issues owner:implementer fresh)
  [ "${#queue[@]}" -gt 0 ] || { echo "[implementer] nothing owned, skipping" | tee -a "$LOGS/loop.log"; return 0; }

  if [ "${#queue[@]}" -ge 2 ]; then
    run_agent implementer triage "$TRIAGE_BUDGET_USD" "$SOURCE_DIR" "$TRIAGE_PROVIDER" "$TRIAGE_MODEL" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER; issues filed by any other login are not yours to work. This is a TRIAGE session: follow the 'Triage session' section of $AGENTS/IMPLEMENTER.agent.md for exactly these issues: $(printf '#%s ' "${queue[@]}"). Do not fix anything in this session. Then stop." \
      "${IMPLEMENTER_FLAGS[@]}"
  fi

  for n in "${queue[@]}"; do
    still_ready "$n" owner:implementer fresh \
      || { echo "[implementer:#$n] no longer ready (handed off or batched), skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent implementer "#$n" "$IMPLEMENTER_BUDGET_USD" "$SOURCE_DIR" "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_MODEL" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER; issues filed by any other login are not yours to work. Follow the role instructions at $AGENTS/IMPLEMENTER.agent.md exactly for this session, working ONLY issue #$n — plus any issue a \`triage:\` comment on #$n tells you to batch with it. Then stop." \
      "${IMPLEMENTER_FLAGS[@]}"
  done
}

# tester_pass — one session per issue to verify, one session per issue handed
# off with no status label (a suite/harness-file change the implementer can't
# make itself), one session per issue bounced back with status:needs-info
# (a question the implementer asked), then (every TESTER_TASK_EVERY cycles)
# one session for closure responses and the standing task.
tester_pass() {
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" owner:tester verify \
      || { echo "[tester:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent tester "#$n" "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Follow the role instructions at $AGENTS/TESTER.agent.md exactly for this session: it is a VERIFY session for issue #$n only (step 2 of your loop). Do not work the standing task. Then stop." \
      "${TESTER_FLAGS[@]}"
  done < <(open_issues owner:tester verify)

  # owner:tester with no status label: not a verify (nothing to run over MCP)
  # and not a wontfix/duplicate closure - a suite-file or other harness-side
  # edit the implementer asked for because it has no checkout of this repo.
  # #194 sat unpicked-up until a human noticed, because neither queue above
  # matches "owner:tester, no status" - this one does, symmetric to the
  # implementer's `fresh` queue.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" owner:tester fresh \
      || { echo "[tester:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent tester "#$n" "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Follow the role instructions at $AGENTS/TESTER.agent.md exactly for this session: it is a HANDOFF session for issue #$n only (step 2h of your loop) - not a verify, nothing to run over MCP. Do not work the standing task. Then stop." \
      "${TESTER_FLAGS[@]}"
  done < <(open_issues owner:tester fresh)

  # owner:tester with status:needs-info: the implementer bounced a question
  # here (IMPLEMENTER.agent.md step 5) - e.g. "what were the job ids of the
  # failed run and the retry". Nothing else schedules these either.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" owner:tester needsinfo \
      || { echo "[tester:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent tester "#$n" "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Follow the role instructions at $AGENTS/TESTER.agent.md exactly for this session: it is an ANSWER session for issue #$n only (step 2a of your loop) - the implementer asked a question via status:needs-info. Do not work the standing task. Then stop." \
      "${TESTER_FLAGS[@]}"
  done < <(open_issues owner:tester needsinfo)

  if [ $((cycle % TESTER_TASK_EVERY)) -eq 0 ]; then
    run_agent tester task "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Follow the role instructions at $AGENTS/TESTER.agent.md exactly for this session: it is a TASK session — first respond to any wontfix/duplicate closures you own (step 3 of your loop), then advance the standing task in $AGENTS/TESTER_TASK.agent.md by one step, filing tickets for anything you hit. Do not re-verify fixed-pending-verify issues here; those get their own sessions. Then stop." \
      "${TESTER_FLAGS[@]}"
  else
    echo "[tester:task] skipped this cycle (TESTER_TASK_EVERY=$TESTER_TASK_EVERY)" | tee -a "$LOGS/loop.log"
  fi
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
  park_external_issues
  before="$(status_board)"

  implementer_pass
  tester_pass

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
