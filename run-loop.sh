#!/usr/bin/env bash
# Drives the implementer and tester Claude Code agents in strictly alternating
# cycles. Both agents communicate only through GitHub Issues on TICKET_REPO.
#
#   ./run-loop.sh                       # run forever
#   MAX_CYCLES=3 SLEEP_SECS=60 ./run-loop.sh
#   IMPLEMENTER_MODEL=haiku TESTER_MODEL=opus ./run-loop.sh
#                                       # per-role models; defaults sonnet / opus
#   TRIAGE_MODEL=sonnet ./run-loop.sh   # triage session's model; defaults to TESTER_MODEL
#   TESTER_EFFORT=high ./run-loop.sh    # per-role --effort; defaults medium (EFFORT)
#   PROVIDER=ollama IMPLEMENTER_MODEL=gemma4:31b-it-q4_K_M TESTER_MODEL=gemma4:31b-it-q4_K_M ./run-loop.sh
#                                       # a non-Anthropic model, served by Ollama
#   DW_URL=... DW_TOKEN=... ./run-loop.sh   # dw MCP endpoint handed to the tester
#   IMPLEMENTER_BUDGET_USD=8 TESTER_BUDGET_USD=5 TRIAGE_BUDGET_USD=3 ./run-loop.sh
#                                       # per-session --max-budget-usd caps (0 = none)
#   TESTER_TASK_EVERY=2 ./run-loop.sh   # standing task every Nth cycle (default 4)
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
#   tester closures      one session, only on a cycle where a wontfix/duplicate
#                        closure the tester hasn't seen is waiting and no task
#                        session runs: responds to those closures (step 3)
#   lead #N (design)     run-features.sh, as a subprocess, when a feature or
#                        idea waits on a design or a decomposition (queues
#                        lead:design and lead:decompose; LEAD_DESIGN_IN_LOOP=0
#                        leaves them to run-features.sh by hand)
#   lead #N              one session per feature stage whose blockers are closed
#                        and whose parent's plan is approved with specs written
#                        (at most LEAD_STAGES_PER_CYCLE): builds, merges,
#                        deploys, hands to the tester (roadmap R11)
#   lead #N closeout     a declined feature's doc move, or a built feature's
#                        design record once every stage is closed
#   tester #N (spec)     one session per feature parent with status:needs-spec:
#                        acceptance cases from the approved plan, before code
#   curator harnest#N    one session per open suite-change request on this repo
#                        not yet sent to Don: rules on it, applies what it
#                        approves, escalates judgment calls (owner:don)
#   tester task          one session, every TESTER_TASK_EVERY cycles: responds
#                        to wontfix/duplicate closures, then advances
#                        the standing task one step
# Why: one 6-issue implementer session measured 269 turns at a 352k-token peak
# and 60M cached-input tokens — issue 6 paid to re-read issues 1-5 on every
# turn. A session's cost is context × turns, and per-issue sessions bound
# both. --max-budget-usd is the backstop for a session that runs away anyway;
# the role prompts tell each agent to leave a resumable trail (branch,
# progress comment) so a cut-off session is picked up, not lost.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The agents' own clone, not Don's working checkout: the implementer switches
# branches, merges and runs tests here, and on 2026-09-22 Don's checkout was
# mid-feature (feat/run-versions) under it. It has its own venv (install.sh).
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"
# Detached worktree of SOURCE_DIR at origin/develop; the consumer roles load
# the dw plugin from here (refresh_plugin_tree in providers.sh).
PLUGIN_TREE="${PLUGIN_TREE:-$HOME/src/dkackman/dw-agent-plugin}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
TICKET_OWNER="${TICKET_OWNER:-dkackman}"   # GitHub login whose issues the agents may act on unasked
HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"   # this repo: where suite-change requests are filed
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
TESTER_MODEL="${TESTER_MODEL:-claude-opus-5-5}"   # exact id, not the "opus" alias: an alias moves on the next release and a verification is only worth the model behind it (see resolved_model)
IMPLEMENTER_PROVIDER="${IMPLEMENTER_PROVIDER:-$PROVIDER}"
TESTER_PROVIDER="${TESTER_PROVIDER:-$PROVIDER}"
# Triage is the implementer's role but not its model by default: a wrong
# wontfix/duplicate/park call doesn't bounce back from the tester, it just
# disappears, and the session is short and capped, so the strong model is
# nearly free there. Follows the tester's model+provider unless set.
TRIAGE_MODEL="${TRIAGE_MODEL:-$TESTER_MODEL}"
TRIAGE_PROVIDER="${TRIAGE_PROVIDER:-$TESTER_PROVIDER}"
# Escalation on bounce. The number of times an issue has already been handed
# off as status:fixed-pending-verify is the number of fixes the tester sent
# back; once it reaches IMPLEMENTER_ESCALATE_AFTER, the next implementer
# session runs on the tester's model+provider, and at IMPLEMENTER_PARK_AFTER
# the driver parks the issue with Don instead of launching a session. Two,
# not one: a first bounce is usually a spec gap the bounce comment closes
# (#265's second round on sonnet was $0.71 against $4.65 for the first), a
# second is the same reviewer rejecting the same model twice. 0 disables.
IMPLEMENTER_ESCALATE_AFTER="${IMPLEMENTER_ESCALATE_AFTER:-2}"
IMPLEMENTER_PARK_AFTER="${IMPLEMENTER_PARK_AFTER:-4}"
# The feature lead (roadmap R11) builds stages here, under the lock, because
# a build deploys; its design and decompose sessions run in run-features.sh.
# Strong model by default, like triage and for the same reason: a wrong
# plan-level call doesn't bounce back, and the lead holds the plan. Its code
# workers are subagents on LEAD_WORKER_MODEL, whose mistakes meet pytest, the
# hand-off gate and the tester.
LEAD_MODEL="${LEAD_MODEL:-$TESTER_MODEL}"
LEAD_PROVIDER="${LEAD_PROVIDER:-$TESTER_PROVIDER}"
LEAD_WORKER_MODEL="${LEAD_WORKER_MODEL:-sonnet}"
# One feature in build at a time (stages from two features interleaving on
# develop make a bounce hard to attribute); a feature's own stages are serial
# through their blocked-by links.
LEAD_STAGES_PER_CYCLE="${LEAD_STAGES_PER_CYCLE:-1}"
# The curator rules on suite-change requests (agents/curator/review.md). The
# strong model by default, for the triage reason: a wrong approval never
# bounces back, because a deleted case just stops catching things. The
# sessions are short.
CURATOR_MODEL="${CURATOR_MODEL:-$TESTER_MODEL}"
CURATOR_PROVIDER="${CURATOR_PROVIDER:-$TESTER_PROVIDER}"
CURATOR_REVIEW_BUDGET_USD="${CURATOR_REVIEW_BUDGET_USD:-3}"
# The docs reviewer verifies fixes that changed only files neither the server
# nor the plugin serves (queue reviewer:docs, the docs-review label), by
# reading the merged tree. It is a verification, so it follows the tester's
# model: a close it makes never comes back to anyone. Sessions are short.
REVIEWER_MODEL="${REVIEWER_MODEL:-$TESTER_MODEL}"
REVIEWER_PROVIDER="${REVIEWER_PROVIDER:-$TESTER_PROVIDER}"
REVIEWER_BUDGET_USD="${REVIEWER_BUDGET_USD:-2}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"   # optional; passed as --fallback-model
# Per-session spend caps (--max-budget-usd; 0 = uncapped) and the context
# size at which a session auto-compacts instead of growing. Non-Anthropic
# providers report zero cost, so a cap never fires there.
IMPLEMENTER_BUDGET_USD="${IMPLEMENTER_BUDGET_USD:-8}"
TESTER_BUDGET_USD="${TESTER_BUDGET_USD:-5}"
TRIAGE_BUDGET_USD="${TRIAGE_BUDGET_USD:-3}"
# A stage is planned at $4-10 of work. The cap is above that, so a stage
# isn't cut off mid-integration; the build prompt says to re-plan a stage
# that turns out bigger than one session. The spec session writes every
# stage's cases in one go.
LEAD_STAGE_BUDGET_USD="${LEAD_STAGE_BUDGET_USD:-15}"
# 1: every cycle runs run-features.sh when a design or decompose waits, so
# Don's hand-back of a plan moves without anyone starting it. 0: by hand only.
LEAD_DESIGN_IN_LOOP="${LEAD_DESIGN_IN_LOOP:-1}"
LEAD_CLOSEOUT_BUDGET_USD="${LEAD_CLOSEOUT_BUDGET_USD:-3}"
TESTER_SPEC_BUDGET_USD="${TESTER_SPEC_BUDGET_USD:-8}"
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"
# The standing task is the most expensive session in a cycle ($1.5-3.7, 50-65
# turns, measured 2026-09-21) and it is discovery, not verification, so it is
# the knob to turn when cost matters. 2 -> 4 halves its amortised cost per
# cycle. Closure responses used to ride only in this session, so they would
# have waited up to four cycles; they now get their own cheap session on any
# cycle where one is pending (see tester_pass).
TESTER_TASK_EVERY="${TESTER_TASK_EVERY:-4}"   # standing task on every Nth cycle
DW_URL="${DW_URL:-http://lem:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"     # dev token; the server is LAN-only
PLUGIN_DIR="$PLUGIN_TREE/plugins/dw"

[ -d "$SOURCE_DIR" ] || { echo "SOURCE_DIR not found: $SOURCE_DIR (clone it: git clone -b develop https://github.com/$TICKET_REPO.git \"$SOURCE_DIR\" && (cd \"$SOURCE_DIR\" && bash ./install.sh))" >&2; exit 1; }
case "$TESTER_TASK_EVERY" in
  ''|0|*[!0-9]*) echo "TESTER_TASK_EVERY must be a whole number >= 1, got '$TESTER_TASK_EVERY'" >&2; exit 1 ;;
esac
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"

. "$REPO/providers.sh"

acquire_driver_lock run-loop
LAST_SESSION="$LOGS/.last-session.loop"
refresh_plugin_tree "$SOURCE_DIR" "$PLUGIN_TREE" >/dev/null \
  || { echo "could not create/refresh the plugin worktree $PLUGIN_TREE from $SOURCE_DIR" >&2; exit 1; }
[ -d "$PLUGIN_DIR" ] || { echo "dw plugin source not found: $PLUGIN_DIR" >&2; exit 1; }

# Per-role effort (--effort). Defaults to EFFORT (providers.sh, `medium` -
# what every session ran at while it was inherited from user settings).
# Triage follows the tester's, like its model does.
IMPLEMENTER_EFFORT="${IMPLEMENTER_EFFORT:-$EFFORT}"
TESTER_EFFORT="${TESTER_EFFORT:-$EFFORT}"
TRIAGE_EFFORT="${TRIAGE_EFFORT:-$TESTER_EFFORT}"
LEAD_EFFORT="${LEAD_EFFORT:-$EFFORT}"
CURATOR_EFFORT="${CURATOR_EFFORT:-$EFFORT}"
REVIEWER_EFFORT="${REVIEWER_EFFORT:-$TESTER_EFFORT}"

# Reject a bad model/provider (or a fallback the role's provider can't serve)
# before the first cycle rather than three minutes into it. This is the only
# guard: run_agent trusts these pairs and never aborts the loop over them.
resolve_model_env "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_MODEL" || exit 1
resolve_model_env "$TESTER_PROVIDER" "$TESTER_MODEL" || exit 1
resolve_model_env "$TRIAGE_PROVIDER" "$TRIAGE_MODEL" || exit 1
resolve_model_env "$LEAD_PROVIDER" "$LEAD_MODEL" || exit 1
resolve_model_env "$CURATOR_PROVIDER" "$CURATOR_MODEL" || exit 1
resolve_model_env "$REVIEWER_PROVIDER" "$REVIEWER_MODEL" || exit 1
validate_fallback_model "$IMPLEMENTER_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$TESTER_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$TRIAGE_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$LEAD_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$CURATOR_PROVIDER" "$FALLBACK_MODEL" || exit 1
validate_fallback_model "$REVIEWER_PROVIDER" "$FALLBACK_MODEL" || exit 1
for e in "$IMPLEMENTER_EFFORT" "$TESTER_EFFORT" "$TRIAGE_EFFORT" "$LEAD_EFFORT" "$CURATOR_EFFORT" "$REVIEWER_EFFORT"; do
  effort_flags anthropic "$e" >/dev/null || exit 1
done

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
# --plugin-dir loads the dw plugin from the plugin tree (origin/develop,
# refreshed before every tester pass) instead of the frozen copy in
# ~/.claude/plugins/cache, so a skill fix merged to develop is testable the
# same cycle without a reinstall. Only the tester needs it; the implementer
# works from the source tree itself.
TESTER_FLAGS=(
  "${MCP_FLAGS[@]}"
  --plugin-dir "$PLUGIN_DIR"
  "${ISOLATION_FLAGS[@]}"
  --tools "$CONSUMER_TOOLS"
  "${CONSUMER_PERMISSION_FLAGS[@]}"
)
# The implementer's shell surface can't be enumerated without breaking a
# cycle the first time it needs sed or pip, so it runs under the auto-mode
# classifier instead: routine work is approved, destructive or exfiltrating
# actions are denied (a headless session never prompts; a denial comes back
# to the agent as a tool result and it routes around or stops). The
# classifier's picture of the environment used to come from Don's user
# settings; ISOLATION_FLAGS cuts those off, so the harness supplies its own.
IMPLEMENTER_FLAGS=(
  "${MCP_FLAGS[@]}"
  "${ISOLATION_FLAGS[@]}"
  --tools "$IMPLEMENTER_TOOLS"
  --settings "$REPO/agent-settings/implementer.json"
  --permission-mode auto
)

# run_agent <role> <tag> <budget_usd> <cwd> <provider> <model> <effort> <kind> <prompt> [extra claude flags...]
# One fresh claude -p session. <role> picks the role prompt's runtime note
# and the per-role log file; <tag> (e.g. "#145", "triage", "task") is what
# distinguishes the sessions of one cycle in loop.log. <kind> picks the role
# prompt for this kind of session (role_prompt in providers.sh: the role's
# core plus that kind's fragments, from agents/<role>/), appended to the
# system prompt so it is in the cached prefix from turn one rather than a
# tool result the agent has to Read first. Streams the agent's output to the terminal,
# its own log, and the combined log.
# Always returns 0 (callers call it bare under set -e). Sets SESSION_OK to 1
# when the session ran to its own end (session_ok in providers.sh), 0
# otherwise, for callers that record "handled" only on success.
SESSION_OK=0
run_agent() {
  local role="$1" tag="$2" budget="$3" dir="$4" provider="$5" model="$6" effort="$7" kind="$8" prompt="$9"; shift 9
  local label="$role:$tag"
  SESSION_OK=0

  # Both pairs were validated at startup, so these can't fail on a bad pair —
  # but a bare failing call in the while body would take the whole driver down
  # under set -e with no log line, so any failure is logged and skipped like a
  # failed session rather than propagated.
  local prompt_file
  if ! resolve_model_env "$provider" "$model" \
     || ! session_flags "$provider" "$model" "$effort" "$budget" \
     || ! prompt_file="$(role_prompt "$role" "$kind" "$LOGS/.prompt.$role.$kind.md")"; then
    echo "[$label] session failed, continuing" | tee -a "$LOGS/loop.log"
    return 0
  fi

  # A per-issue session is fingerprinted before and after, for the
  # no-progress ledger (note_progress in providers.sh).
  local issue_repo="" issue_n="" before=""
  case "$tag" in
    "#"*)        issue_repo="$TICKET_REPO";  issue_n="${tag#\#}" ;;
    "harnest#"*) issue_repo="$HARNESS_REPO"; issue_n="${tag#harnest#}" ;;
  esac
  [ -z "$issue_n" ] || before="$(issue_fingerprint "$issue_repo" "$issue_n")"

  # Each agent is a fresh session, so its model is otherwise unrecorded: the
  # runtime note says it in the prompt, where the agent carries it into the
  # comments it writes. HARNEST_SESSION_KIND reaches the guard hook
  # (guard.py), which allows a tester handoff to close without an MCP call.
  local -a SESSION_ENV=(HARNEST_SESSION_KIND="$kind")
  SESSION_HEADER="cycle $cycle: $label" run_claude_session "$label" "$role" "$dir" "$prompt_file" \
    "$prompt

$(runtime_note "$role" "$provider" "$model")" "${SESSION_FLAGS[@]}" "$@"

  session_ok "$LAST_SESSION" && SESSION_OK=1
  # A per-issue session ("#145") gets its issue audited against the label
  # invariants; triage/task/closures sessions span several issues and don't.
  case "$tag" in "#"*) audit_issue "${tag#\#}" "$role" ;; esac
  if [ -n "$issue_n" ] && session_ran "$LAST_SESSION"; then
    note_progress "$issue_repo" "$issue_n" "$before" "$label" "$role:$kind"
  fi
  return 0
}

# Queues come from lib/classify.jq through queue_issues and still_ready
# (providers.sh): one state machine for every driver, the digest and the
# audit. The closure ledger below is the one queue it doesn't cover: those
# issues are closed.

# pending_closures
# Numbers of closed issues carrying owner:tester plus wontfix or duplicate
# that no tester session has been dispatched for yet (agents/tester/closures.md: accept, or reopen once with new evidence). Whether the tester has
# *responded* is only visible in the comments, so the driver keeps its own
# ledger, logs/closures-seen, of the numbers it has already handed to a
# session - mark_closures_seen appends to it after the closure or task
# session runs. A reopened issue that comes back wontfix a second time is
# already in the ledger, which matches the rule that a second wontfix is
# final. Honours ONLY_ISSUES like the queues do.
# The label filter is in the query, one query per closing label: filtering
# afterwards meant listing every closed owner:tester issue - verified ones
# keep the label - and at 181 of them (2026-09-22) the --limit 200 window was
# about to start silently dropping older wontfix closures.
pending_closures() {
  local out seen="$LOGS/closures-seen" l
  out="$(for l in wontfix duplicate; do
      gh issue list --repo "$TICKET_REPO" --state closed --label owner:tester --label "$l" \
        --limit 500 --json number --jq '.[].number'
    done | sort -nu)"
  if [ -n "$ONLY_ISSUES" ]; then
    local pat
    pat="$(printf '%s' "$ONLY_ISSUES" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//;s/ /|/g')"
    out="$(printf '%s\n' "$out" | grep -E "^($pat)$" || true)"
  fi
  [ -r "$seen" ] && out="$(printf '%s\n' "$out" | grep -vxF -f "$seen" || true)"
  [ -n "$out" ] && printf '%s\n' "$out"
}

mark_closures_seen() {
  [ $# -eq 0 ] || printf '%s\n' "$@" >> "$LOGS/closures-seen"
}

# issue_context lives in providers.sh (shared with run-features.sh).

# deployed_head lives in providers.sh (run-regression.sh records it too).

# check_lem_on_develop
# lem can only be on one commit, and a cycle hands off several fixes, so the
# implementer merges each fix into develop and deploys develop (its role
# prompt, step 3c/3d). If lem is on anything else when the tester's turn
# comes, the tester is about to verify against a server missing some of the
# fixes it was handed (2026-09-21: three fix branches deployed one over the
# other, then a fourth session deployed develop, which had none of them).
# The remedy is one idempotent call, so the driver makes it (deploy.sh waits
# for a running job and polls health) rather than leaving a warning for a
# human who isn't watching; a failed deploy is logged and the tester still
# runs, since its prompt names what lem is running and it can bounce a
# mismatch. DEPLOY_ON_MISMATCH=0 reverts to warning only.
DEPLOY_ON_MISMATCH="${DEPLOY_ON_MISMATCH:-1}"
# lem reports an abbreviated hash whose length git picks from the repo's
# size, so it is compared as a prefix of the full one, never against a
# fixed-length cut (a 7-character cut stops matching the day lem's clone
# starts printing 8, and every cycle would then redeploy).
check_lem_on_develop() {
  local want lem_sha
  want="$(git -C "$SOURCE_DIR" ls-remote -q origin refs/heads/develop 2>/dev/null | cut -f1 || true)"
  [ -n "$want" ] || return 0
  case "$DEPLOYED_HEAD" in
    "develop @ "?*)
      lem_sha="${DEPLOYED_HEAD#develop @ }"
      case "$want" in "$lem_sha"*) return 0 ;; esac ;;
  esac
  echo "[loop] WARNING: lem is on '$DEPLOYED_HEAD' but origin/develop is ${want:0:10} — the tester would verify against a server that may lack this cycle's fixes" | tee -a "$LOGS/loop.log"
  [ "$DEPLOY_ON_MISMATCH" = 1 ] || return 0
  echo "[loop] deploying develop to lem" | tee -a "$LOGS/loop.log"
  # shellcheck disable=SC2088  # the ~ is for lem's shell, not ours
  if ssh -o ConnectTimeout=8 -o BatchMode=yes lem '~/diffusers-workflow/scripts/deploy.sh develop' 2>&1 \
       | tail -n 3 | sed -u 's/^/[loop:deploy] /' | tee -a "$LOGS/loop.log"; then
    DEPLOYED_HEAD="$(deployed_head)"
    echo "[loop] lem is running: $DEPLOYED_HEAD (after driver deploy)" | tee -a "$LOGS/loop.log"
  else
    echo "[loop] driver deploy of develop failed; the tester runs against '$DEPLOYED_HEAD'" | tee -a "$LOGS/loop.log"
  fi
}

# set_base_commit
# Exports HARNEST_BASE_COMMIT, origin/develop as of now, for the R3 hand-off
# gate (guard.py), which fails a hand-off only for test failures the session
# introduced. When it can't be read the gate runs without that comparison, so
# say so in the log rather than leave it silent.
set_base_commit() {
  git -C "$SOURCE_DIR" fetch -q origin develop 2>/dev/null || true
  HARNEST_BASE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse -q --verify origin/develop 2>/dev/null || true)"
  export HARNEST_BASE_COMMIT
  [ -n "$HARNEST_BASE_COMMIT" ] \
    || echo "[loop] WARNING: could not read origin/develop; the hand-off gate skips its tests-vs-base check this session" | tee -a "$LOGS/loop.log"
}

# implementer_pass — triage (when 2+ issues wait), then one session per issue.
implementer_pass() {
  local -a queue=()
  local n
  while IFS= read -r n; do [ -n "$n" ] && queue+=("$n"); done < <(queue_issues implementer:fix | cut -f1)
  [ "${#queue[@]}" -gt 0 ] || { echo "[implementer] nothing owned, skipping" | tee -a "$LOGS/loop.log"; return 0; }

  if [ "${#queue[@]}" -ge 2 ]; then
    run_agent implementer triage "$TRIAGE_BUDGET_USD" "$SOURCE_DIR" "$TRIAGE_PROVIDER" "$TRIAGE_MODEL" "$TRIAGE_EFFORT" triage \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER; issues filed by any other login are not yours to work. This is a TRIAGE session: your role instructions for it are in your system prompt; triage exactly these issues: $(printf '#%s ' "${queue[@]}"). Do not fix anything in this session. Then stop.

lem is running: $DEPLOYED_HEAD (as of $(ts)).

The issues as of $(ts), bodies only — start from these; gh is for acting on them, for their comments, and for anything newer:

$(for q in "${queue[@]}"; do issue_context "$q" brief; echo; done)" \
      "${IMPLEMENTER_FLAGS[@]}"
    for n in "${queue[@]}"; do audit_issue "$n" implementer; done
  fi

  local bounces model provider escalation last_on=""
  # Only claim the last attempt ran on the tester's model when escalation
  # was actually on and would have fired before parking.
  if [ "$IMPLEMENTER_ESCALATE_AFTER" -gt 0 ] && [ "$IMPLEMENTER_ESCALATE_AFTER" -lt "$IMPLEMENTER_PARK_AFTER" ]; then
    last_on=", the most recent on the tester's own model"
  fi
  for n in "${queue[@]}"; do
    still_ready "$n" implementer:fix \
      || { echo "[implementer:#$n] no longer ready (handed off or batched), skipping" | tee -a "$LOGS/loop.log"; continue; }
    bounces="$(handoff_count "$n")"
    model="$IMPLEMENTER_MODEL"; provider="$IMPLEMENTER_PROVIDER"; escalation=""
    if [ "$IMPLEMENTER_PARK_AFTER" -gt 0 ] && [ "$bounces" -ge "$IMPLEMENTER_PARK_AFTER" ]; then
      echo "[implementer:#$n] bounced $bounces times; parking with owner:don instead of another retry" | tee -a "$LOGS/loop.log"
      gh issue edit "$n" --repo "$TICKET_REPO" --remove-label owner:implementer --add-label owner:don --add-label status:needs-approval >/dev/null \
        && gh issue comment "$n" --repo "$TICKET_REPO" --body "Parked by the loop driver: this issue has been handed off as fixed and bounced back by the tester $bounces times since it was last opened (IMPLEMENTER_PARK_AFTER=$IMPLEMENTER_PARK_AFTER)$last_on. The two roles are not converging on what \"fixed\" means here; a human should look at the bounce comments and either narrow the ask or say which side is right, then hand it back with \`owner:implementer\`." >/dev/null \
        || echo "[implementer:#$n] could not park (gh failed); skipping this cycle" | tee -a "$LOGS/loop.log"
      continue
    elif [ "$IMPLEMENTER_ESCALATE_AFTER" -gt 0 ] && [ "$bounces" -ge "$IMPLEMENTER_ESCALATE_AFTER" ]; then
      model="$TESTER_MODEL"; provider="$TESTER_PROVIDER"
      echo "[implementer:#$n] bounced $bounces times; escalating this session to $provider/$model" | tee -a "$LOGS/loop.log"
      escalation="

This issue has been handed off as fixed and sent back by the tester $bounces times. You are running on a stronger model than the sessions that produced those fixes, for that reason — say so in your hand-off comment. Read every bounce comment before touching code: the tester's objections are the specification now, and a fix that satisfies the original text but not those comments will bounce again."
    fi
    set_base_commit
    run_agent implementer "#$n" "$IMPLEMENTER_BUDGET_USD" "$SOURCE_DIR" "$provider" "$model" "$IMPLEMENTER_EFFORT" fix \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER; issues filed by any other login are not yours to work. This is a fix session: your role instructions for it are in your system prompt; follow them exactly, working ONLY issue #$n — plus any issue a \`triage:\` comment on #$n tells you to batch with it. Then stop.$escalation

lem is running: $DEPLOYED_HEAD (as of $(ts)).

The issue as of $(ts) — start from this rather than fetching it; gh is for acting on it and for anything newer:

$(issue_context "$n")" \
      "${IMPLEMENTER_FLAGS[@]}"
  done
}

# features_pass — the lead's design and decompose sessions, by running
# run-features.sh (the one place they are defined) when either queue holds an
# issue. Before lead_pass and tester_pass, so a decompose this cycle gets its
# spec session this cycle. The sessions are read-only and take no lock; running
# them here only puts them in the cycle, so a hand-back from Don isn't left
# waiting for someone to start run-features.sh. Its own queue read decides
# which issues run; this check only saves starting it for nothing.
features_pass() {
  [ "$LEAD_DESIGN_IN_LOOP" = 1 ] || return 0
  [ -n "$(queue_issues lead:design; queue_issues lead:decompose)" ] || return 0
  env LEAD_MODEL="$LEAD_MODEL" LEAD_PROVIDER="$LEAD_PROVIDER" LEAD_EFFORT="$LEAD_EFFORT"     PROVIDER="$PROVIDER" SOURCE_DIR="$SOURCE_DIR" TICKET_REPO="$TICKET_REPO"     TICKET_OWNER="$TICKET_OWNER" DW_URL="$DW_URL" DW_TOKEN="$DW_TOKEN"     FALLBACK_MODEL="$FALLBACK_MODEL" AUTOCOMPACT_TOKENS="$AUTOCOMPACT_TOKENS"     ONLY_ISSUES="$ONLY_ISSUES" "$REPO/run-features.sh"
}

# lead_pass — the feature lead's build and close-out sessions (roadmap R11).
# Runs after the implementer pass and before the tester pass, so a stage
# handed off this cycle is verified this cycle, and lem is re-checked
# against develop in between as for any fix.
lead_pass() {
  local n parent built=0 bounces
  local -a stages=()
  while IFS= read -r n; do [ -n "$n" ] && stages+=("$n"); done < <(queue_issues lead:build | cut -f1,2 | tr '\t' ' ')
  for n in ${stages[@]+"${stages[@]}"}; do
    [ "$built" -lt "$LEAD_STAGES_PER_CYCLE" ] || break
    parent="${n#* }"; n="${n%% *}"
    bounces="$(handoff_count "$n")"
    if [ "$IMPLEMENTER_PARK_AFTER" -gt 0 ] && [ "$bounces" -ge "$IMPLEMENTER_PARK_AFTER" ]; then
      echo "[lead:#$n] stage bounced $bounces times; parking with owner:don" | tee -a "$LOGS/loop.log"
      gh issue edit "$n" --repo "$TICKET_REPO" --remove-label owner:lead --add-label owner:don --add-label status:needs-approval >/dev/null \
        && gh issue comment "$n" --repo "$TICKET_REPO" --body "Parked by the loop driver: this stage of #$parent has been handed off and bounced back by the tester $bounces times since it was last opened (IMPLEMENTER_PARK_AFTER=$IMPLEMENTER_PARK_AFTER). The lead and the tester's acceptance cases are not converging; a human should read the bounce comments and either amend the plan (a new version on #$parent) or say which side is right, then hand it back with \`owner:lead\`." >/dev/null \
        || echo "[lead:#$n] could not park (gh failed)" | tee -a "$LOGS/loop.log"
      continue
    fi
    set_base_commit
    run_agent lead "#$n" "$LEAD_STAGE_BUDGET_USD" "$SOURCE_DIR" "$LEAD_PROVIDER" "$LEAD_MODEL" "$LEAD_EFFORT" build \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER. This is a BUILD session for stage #$n of feature #$parent only: your role instructions for it are in your system prompt. Run code-writing subagents on model \"$LEAD_WORKER_MODEL\" unless the stage says otherwise.$([ "$bounces" -gt 0 ] && printf ' This stage has been handed off and sent back %s time(s): read every bounce comment before touching code.' "$bounces") Then stop.

lem is running: $DEPLOYED_HEAD (as of $(ts)).

The stage issue as of $(ts):

$(issue_context "$n")

## The approved plan on #$parent, in full

$(plan_text "$parent")" \
      "${IMPLEMENTER_FLAGS[@]}"
    built=$((built + 1))
  done

  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" lead:closeout \
      || { echo "[lead:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    # A parent the tester keeps failing at the final check goes to Don, the
    # same threshold as a stage. The close-out prompt files a fix-forward
    # stage for each failure, which takes the parent out of this queue until
    # it closes, so this only fires if that isn't converging either.
    bounces="$(handoff_count "$n")"
    if [ "$IMPLEMENTER_PARK_AFTER" -gt 0 ] && [ "$bounces" -ge "$IMPLEMENTER_PARK_AFTER" ]; then
      echo "[lead:#$n] feature failed its final check $bounces times; parking with owner:don" | tee -a "$LOGS/loop.log"
      gh issue edit "$n" --repo "$TICKET_REPO" --remove-label owner:lead --add-label owner:don --add-label status:needs-approval >/dev/null \
        && gh issue comment "$n" --repo "$TICKET_REPO" --body "Parked by the loop driver: this feature has been handed to the tester for its final check and failed it $bounces times (IMPLEMENTER_PARK_AFTER=$IMPLEMENTER_PARK_AFTER). A human should read the bounce comments and decide." >/dev/null \
        || echo "[lead:#$n] could not park (gh failed)" | tee -a "$LOGS/loop.log"
      continue
    fi
    # A built close-out hands the parent to the tester through the same R3
    # gate as a fix, which compares against develop as of this session.
    set_base_commit
    run_agent lead "#$n" "$LEAD_CLOSEOUT_BUDGET_USD" "$SOURCE_DIR" "$LEAD_PROVIDER" "$LEAD_MODEL" "$LEAD_EFFORT" closeout \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER. This is a CLOSE-OUT session for feature #$n only: your role instructions for it are in your system prompt. Its labels say which close-out it is (wontfix: declined; otherwise every stage is closed). Then stop.

The issue as of $(ts):

$(issue_context "$n")

## The plan on #$n, in full

$(plan_text "$n")" \
      "${IMPLEMENTER_FLAGS[@]}"
  done < <(queue_issues lead:closeout | cut -f1)
}

# tester_pass — one session per issue to verify, one session per issue handed
# off with no status label (a suite/harness-file change the implementer can't
# make itself), one session per issue bounced back with status:needs-info
# (a question the implementer asked), then (every TESTER_TASK_EVERY cycles)
# one session for closure responses and the standing task.
tester_pass() {
  local n
  # A feature parent waiting on acceptance cases (roadmap R11 phase 3): the
  # approved plan in full plus the stage list, never any code.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" tester:spec \
      || { echo "[tester:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent tester "#$n" "$TESTER_SPEC_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" "$TESTER_EFFORT" spec \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Your role instructions for this kind of session are in your system prompt; follow them exactly: it is a SPEC session for feature #$n only - write its stages' acceptance cases from the approved plan. Do not verify anything and do not work the standing task. Then stop.

The feature issue as of $(ts):

$(issue_context "$n")

## Its stages (sub-issues), in number order

$(gh issue view "$n" --repo "$TICKET_REPO" --json subIssues --jq '.subIssues.nodes[] | "#\(.number) \(.title)"' 2>/dev/null || echo "(could not list; gh issue view $n --json subIssues)")

## The approved plan, in full

$(plan_text "$n")" \
      "${TESTER_FLAGS[@]}"
  done < <(queue_issues tester:spec | cut -f1)

  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" tester:verify \
      || { echo "[tester:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent tester "#$n" "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" "$TESTER_EFFORT" verify \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Your role instructions for this kind of session are in your system prompt; follow them exactly: it is a VERIFY session for issue #$n only. Do not work the standing task. Then stop.

lem is running: $DEPLOYED_HEAD (as of $(ts)).

The issue as of $(ts) — start from this rather than fetching it; gh is for acting on it and for anything newer:

$(issue_context "$n")" \
      "${TESTER_FLAGS[@]}"
  done < <(queue_issues tester:verify | cut -f1)

  # owner:tester with no status label: not a verify (nothing to run over MCP)
  # and not a wontfix/duplicate closure - a suite-file or other harness-side
  # edit the implementer asked for because it has no checkout of this repo.
  # #194 sat unpicked-up until a human noticed, because neither queue above
  # matches "owner:tester, no status" - this one does, symmetric to the
  # implementer's `fresh` queue.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" tester:handoff \
      || { echo "[tester:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent tester "#$n" "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" "$TESTER_EFFORT" handoff \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Your role instructions for this kind of session are in your system prompt; follow them exactly: it is a HANDOFF session for issue #$n only - not a verify, nothing to run over MCP. Do not work the standing task. Then stop.

lem is running: $DEPLOYED_HEAD (as of $(ts)).

The issue as of $(ts) — start from this rather than fetching it; gh is for acting on it and for anything newer:

$(issue_context "$n")" \
      "${TESTER_FLAGS[@]}"
  done < <(queue_issues tester:handoff | cut -f1)

  # owner:tester with status:needs-info: the implementer bounced a question
  # here (agents/implementer/core.md, "Needs info") - e.g. "what were the job ids of the
  # failed run and the retry". Nothing else schedules these either.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" tester:answer \
      || { echo "[tester:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent tester "#$n" "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" "$TESTER_EFFORT" answer \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Your role instructions for this kind of session are in your system prompt; follow them exactly: it is an ANSWER session for issue #$n only - the implementer asked a question via status:needs-info. Do not work the standing task. Then stop.

lem is running: $DEPLOYED_HEAD (as of $(ts)).

The issue as of $(ts) — start from this rather than fetching it; gh is for acting on it and for anything newer:

$(issue_context "$n")" \
      "${TESTER_FLAGS[@]}"
  done < <(queue_issues tester:answer | cut -f1)

  # Closure responses (step 3) ride in the task session when one runs this
  # cycle; on the other cycles a pending closure gets a short session of its
  # own, so raising TESTER_TASK_EVERY slows discovery but not the reopen
  # window. Either way the driver's ledger is updated afterwards.
  local -a closures=()
  while IFS= read -r n; do [ -n "$n" ] && closures+=("$n"); done < <(pending_closures)

  local clist="none pending" freeze
  [ "${#closures[@]}" -eq 0 ] || clist="$(printf '#%s ' "${closures[@]}")"
  # A release freeze holds discovery too: the standing task files new issues,
  # and nothing but release-blockers moves until the release ships (R14)
  freeze="$(release_freeze)"
  if [ -n "$freeze" ] && [ $((cycle % TESTER_TASK_EVERY)) -eq 0 ]; then
    echo "[tester:task] held: release freeze $freeze" | tee -a "$LOGS/loop.log"
  fi
  if [ -z "$freeze" ] && [ $((cycle % TESTER_TASK_EVERY)) -eq 0 ]; then
    run_agent tester task "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" "$TESTER_EFFORT" task \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Your role instructions for this kind of session are in your system prompt; follow them exactly: it is a TASK session — first respond to the wontfix/duplicate closures you own ($clist), then advance the standing task by one step, filing tickets for anything you hit. Do not re-verify fixed-pending-verify issues here; those get their own sessions. Then stop." \
      "${TESTER_FLAGS[@]}"
    # Only when the session ran to its end: a closure has one chance at a
    # reopen, and a died or cut-off session may not have reached it.
    [ "$SESSION_OK" = 1 ] && mark_closures_seen ${closures[@]+"${closures[@]}"}
  elif [ "${#closures[@]}" -gt 0 ]; then
    local list
    list="$(printf '#%s ' "${closures[@]}")"
    run_agent tester closures "$TESTER_BUDGET_USD" "$REPO" "$TESTER_PROVIDER" "$TESTER_MODEL" "$TESTER_EFFORT" closures \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Your role instructions for this kind of session are in your system prompt; follow them exactly: it is a CLOSURES session for ${list}only - each was closed wontfix or duplicate with owner:tester; accept, or reopen once with materially new evidence. Do not work the standing task and do not verify anything. Then stop." \
      "${TESTER_FLAGS[@]}"
    [ "$SESSION_OK" = 1 ] && mark_closures_seen "${closures[@]}"
    echo "[tester:task] skipped this cycle (TESTER_TASK_EVERY=$TESTER_TASK_EVERY)" | tee -a "$LOGS/loop.log"
  elif [ -z "$freeze" ]; then
    echo "[tester:task] skipped this cycle (TESTER_TASK_EVERY=$TESTER_TASK_EVERY)" | tee -a "$LOGS/loop.log"
  fi
}

# reviewer_pass — one docs review per fix the tester can't observe: handed
# off with the docs-review label because it changed only files neither the
# server nor the plugin serves (#420 sat with Don for want of this: the
# tester, correctly, could neither see the README nor read the diff). The
# reviewer reads the merged tree, so its cwd is the plugin tree, the
# driver's detached worktree at origin/develop, refreshed just before the
# tester pass. Read-only: it can't change the tree it reviews. Setting
# sources are local only, not ISOLATION_FLAGS' project,local: the dw repo's
# checked-in .claude/settings.json allows pip install, pytest and curl, and
# under dontAsk a project allow rule would widen this allowlist.
reviewer_pass() {
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    still_ready "$n" reviewer:docs \
      || { echo "[reviewer:#$n] no longer ready, skipping" | tee -a "$LOGS/loop.log"; continue; }
    run_agent reviewer "#$n" "$REVIEWER_BUDGET_USD" "$PLUGIN_TREE" "$REVIEWER_PROVIDER" "$REVIEWER_MODEL" "$REVIEWER_EFFORT" docs \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. Your role instructions for this kind of session are in your system prompt; follow them exactly: it is a DOCS REVIEW session for issue #$n only. Then stop.

Your working directory is the merged tree at origin/develop @ $(git -C "$PLUGIN_TREE" rev-parse --short HEAD 2>/dev/null || echo unknown).

The issue as of $(ts) — start from this rather than fetching it; gh is for acting on it and for anything newer:

$(issue_context "$n")" \
      "${MCP_FLAGS[@]}" --setting-sources local --tools "$REVIEWER_TOOLS" "${REVIEWER_PERMISSION_FLAGS[@]}"
  done < <(queue_issues reviewer:docs | cut -f1)
}

# curator_pass — one review session per suite-change request on this repo
# (an open `suite` issue not waiting on Don), then a commit
# of whatever it applied, under the curator's name and naming the request.
# In the loop, under its lock, because approvals edit the suite files: a
# regression run reads them, and the drivers commit them.
curator_pass() {
  local n
  local -a reqs=()
  # Not filtered on status:needs-approval: Don hands an escalation back by
  # removing owner:don, and often clears the status too. Any open request
  # not with him is for the curator. (No comments inside the <( ) below:
  # bash 3.2 misparses an apostrophe in a comment there.)
  while IFS= read -r n; do [ -n "$n" ] && reqs+=("$n"); done < <(
    gh issue list --repo "$HARNESS_REPO" --state open --limit 100 --label suite \
      --json number,labels,author \
      --jq ".[] | select(.author.login == \"$TICKET_OWNER\") | select([.labels[].name] | index(\"owner:don\") == null) | .number" 2>/dev/null \
    | sort -n | only_issues_filter)
  for n in ${reqs[@]+"${reqs[@]}"}; do
    run_agent curator "harnest#$n" "$CURATOR_REVIEW_BUDGET_USD" "$REPO" "$CURATOR_PROVIDER" "$CURATOR_MODEL" "$CURATOR_EFFORT" review \
      "This is a REVIEW session for suite-change request #$n on $HARNESS_REPO (this repo) only: your role instructions for it are in your system prompt. Case history lives on the ticket repo, $TICKET_REPO. Then stop.

The request as of $(ts):

$(TICKET_REPO="$HARNESS_REPO" issue_context "$n")" \
      "${MCP_FLAGS[@]}" "${ISOLATION_FLAGS[@]}" --tools "$CURATOR_REVIEW_TOOLS" "${CURATOR_REVIEW_PERMISSION_FLAGS[@]}"
    co_author_for "$CURATOR_PROVIDER" "$(resolved_model curator "$CURATOR_MODEL")"
    commit_suite_changes "regression: curator applied $HARNESS_REPO#$n" "$CO_AUTHOR" "$CO_AUTHOR_EMAIL" \
      || echo "[curator] suite commit failed, continuing" | tee -a "$LOGS/loop.log"
  done
}

# One line per open issue: #NN  status-labels  owner-label  title. Prints
# nothing when gh fails: the board is a report, never a reason to stop.
status_board() {
  gh issue list --repo "$TICKET_REPO" --state open --limit 200 \
    --json number,title,labels \
    --jq '.[] | [
      ("#" + (.number|tostring)),
      (([.labels[].name | select(startswith("status:"))]) + ["open"])[0],
      (([.labels[].name | select(startswith("owner:"))]) + ["unowned"])[0],
      .title
    ] | @tsv' \
  | awk -F'\t' '{printf "  %-5s %-24s %-18s %s\n", $1, $2, $3, $4}' || true
}

# step <name> <command...>
# Runs one top-level step of a cycle. A failure is logged and the cycle goes
# on: this driver runs forever, and one GitHub or network blip must not
# stop it. (Inside a step, set -e is off, as it is for any command on the
# left of ||, so a step keeps going past a failed command too. Each step is
# a pass over independent issues, so that is what's wanted.)
step() {
  local name="$1"; shift
  "$@" || echo "[loop] WARNING: $name failed (exit $?); continuing the cycle" | tee -a "$LOGS/loop.log"
}

# main: the cycle loop. In a function, and called with `exit` on the same
# line, so bash has parsed the whole of it before it runs, and editing this
# file while the loop is live can't make bash resume at a stale byte offset.
# An edit takes effect at the next start.
main() {
cycle=0
while true; do
  cycle=$((cycle + 1))
  step park_external_issues park_external_issues
  before="$(status_board)"
  DEPLOYED_HEAD="$(deployed_head)"
  echo "[loop] lem is running: $DEPLOYED_HEAD" | tee -a "$LOGS/loop.log"

  step implementer_pass implementer_pass
  step features_pass features_pass
  step lead_pass lead_pass
  # Refresh after the implementer's and lead's deploys: the tester must be told what it
  # is actually verifying against, not what lem ran when the cycle began.
  DEPLOYED_HEAD="$(deployed_head)"
  echo "[loop] lem is running: $DEPLOYED_HEAD (after implementer pass)" | tee -a "$LOGS/loop.log"
  step check_lem_on_develop check_lem_on_develop
  # Same commit as lem, for the plugin: pick up this cycle's merged skill fixes.
  if plugin_at="$(refresh_plugin_tree "$SOURCE_DIR" "$PLUGIN_TREE")"; then
    echo "[loop] tester plugin tree: origin/develop @ $plugin_at" | tee -a "$LOGS/loop.log"
  else
    echo "[loop] WARNING: could not refresh the plugin tree; the tester loads the previous one" | tee -a "$LOGS/loop.log"
  fi
  step tester_pass tester_pass
  # After the tester: a verify that finds a docs-only fix it can't observe
  # reroutes it here (docs-review), and it is reviewed the same cycle.
  step reviewer_pass reviewer_pass

  # The tester is the only agent in this loop that edits the regression suite
  # files (it adds a case once it has verified it over MCP; the implementer
  # only proposes one in a hand-off comment). Commit whatever it added this
  # cycle under its own identity, so the trailer names the model that wrote
  # the case. A no-op when the suite files are clean.
  co_author_for "$TESTER_PROVIDER" "$(resolved_model tester "$TESTER_MODEL")"
  commit_suite_changes "regression: tester added case (cycle $cycle)" "$CO_AUTHOR" "$CO_AUTHOR_EMAIL" \
    || echo "[tester] suite commit failed, continuing" | tee -a "$LOGS/loop.log"
  step curator_pass curator_pass

  { echo "--- $(ts) cycle $cycle tickets ---"; status_board
    freeze="$(release_freeze)"; [ -z "$freeze" ] || echo "  release freeze $freeze: only release-blocker issues move"
  } | tee -a "$LOGS/loop.log"

  if [ "$MAX_CYCLES" -gt 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ]; then
    echo "Reached MAX_CYCLES=$MAX_CYCLES, exiting." | tee -a "$LOGS/loop.log"
    break
  fi
  # A clean stop at the next cycle boundary, for a release freeze: every
  # session this cycle started has finished and been audited, and nothing of
  # the next has begun. Consumed, so a restart doesn't stop at once (R14;
  # the 0.4.0 freeze was a hand-rolled watcher on the board line).
  if [ -e "$LOGS/stop-after-cycle" ]; then
    rm -f "$LOGS/stop-after-cycle"
    echo "stop-after-cycle found, exiting after cycle $cycle." | tee -a "$LOGS/loop.log"
    break
  fi

  if [ "$(status_board)" != "$before" ]; then
    echo "tickets changed this cycle, starting next cycle now" | tee -a "$LOGS/loop.log"
  else
    echo "idle, sleeping ${SLEEP_SECS}s" | tee -a "$LOGS/loop.log"
    sleep "$SLEEP_SECS"
  fi
done
}

main "$@"; exit
