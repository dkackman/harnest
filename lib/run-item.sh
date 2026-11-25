#!/usr/bin/env bash
# lib/run-item.sh <pass> <queue> <issue>   a per-issue pass
# lib/run-item.sh tester-task|tester-closures
# lib/run-item.sh park <issue> <reason>
# lib/run-item.sh park-external|unpark|consolidation|housekeeping|labels
# One pass of run-loop.sh for one issue, as a child of the Python scheduler
# (harness/drivers/loop.py, R17). It sources run-loop.sh in item mode
# (HARNEST_ITEM=1): no driver lock, no deploy, no suite commit, no cycle loop.
# The scheduler holds the lock, owns every deploy, lands suite edits from the
# session's tree (harness/suite_tree.py) and reads the board for the outcome.
#
# The queue is part of a per-issue item: the pass runs only that queue's
# branch (HARNEST_ITEM_QUEUE, item_queue_allows in providers.sh), for exactly
# <issue> (ONLY_ISSUES, matched exactly in item mode: a feature parent's item
# never runs its stages' sessions, which are items of their own).
#
# Per-issue passes and the queues each takes (lib/classify.jq's names):
#   implementer      implementer:fix (a stranded issue's triage rides in it)
#   triage           the same pass and queue
#   lead             lead:build or lead:closeout
#   features         lead:design or lead:decompose (run-features.sh)
#   tester           tester:spec, tester:verify, tester:handoff or tester:answer
#   reviewer-arch    reviewer:arch
#   reviewer-docs    reviewer:docs
#   delegate         delegate:rule (R19: one owner:don ask, for Don)
#   delegate-suite   delegate:suite (R19: one suite request on HARNESS_REPO
#                    the curator escalated to Don)
#   curator          curator (one suite-change request on HARNESS_REPO)
# Issue-less passes:
#   tester-task      the standing task, now (TESTER_PART=task)
#   tester-closures  the closures session (TESTER_PART=closures)
#   park             park_issue <issue> <reason>: with Don, for the driver
#   park-external    park_external_issues
#   unpark           unpark_pass
#   consolidation    consolidation_pass
#   housekeeping     park-external, unpark and consolidation, in one go (the
#                    scheduler's once-a-poll housekeeping)
#   labels           the claim and backend labels the loop makes at startup
#
# Environment, from the scheduler: DW_TARGET, HARNEST_LAST_SESSION
# (logs/.last-session.item.<slot>), DEPLOYED_HEAD, HARNEST_DW_FROZEN (0|1,
# dw_frozen as of the last poll), HARNEST_SESSION_TREE and
# HARNEST_SESSION_BASE (a tester or curator item only), and every role knob
# run-loop.sh reads. ONLY_ISSUES and HARNEST_ITEM_QUEUE are set here.
# A tester or curator item leaves <last-session>.land (JSON: msg, kind, name,
# email) for the scheduler's suite_tree.land.
#
# Exit: 0 when a session ran or nothing was ready, 1 on a driver error.

usage="usage: run-item.sh <pass> <queue> <issue> | tester-task | tester-closures | park <issue> <reason> | park-external | unpark | consolidation | housekeeping | labels"
item_queue=""
case "${1:-}" in
  implementer|triage|lead|features|tester|reviewer-arch|reviewer-docs|delegate|delegate-suite|curator)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "run-item.sh: $1 is a per-issue pass and needs <queue> <issue>; $usage" >&2; exit 1; }
    case "$1:$2" in
      implementer:implementer:fix|triage:implementer:fix|lead:lead:build|lead:lead:closeout) ;;
      features:lead:design|features:lead:decompose|curator:curator) ;;
      tester:tester:spec|tester:tester:verify|tester:tester:handoff|tester:tester:answer) ;;
      reviewer-arch:reviewer:arch|reviewer-docs:reviewer:docs|delegate:delegate:rule|delegate-suite:delegate:suite) ;;
      *) echo "run-item.sh: queue '$2' is not the $1 pass's" >&2; exit 1 ;;
    esac
    item_queue="$2"; set -- "$1" "$3" ;;
  park) [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "usage: run-item.sh park <issue> <reason>" >&2; exit 1; } ;;
  tester-task|tester-closures|park-external|unpark|consolidation|housekeeping|labels) ;;
  *) echo "$usage" >&2; exit 1 ;;
esac
[ -n "${HARNEST_LAST_SESSION:-}" ] \
  || { echo "run-item.sh: HARNEST_LAST_SESSION is not set; each item needs its own last-session file (logs/.last-session.item.<slot>)" >&2; exit 1; }
case "${2:-}" in ''|*[!0-9]*) [ -z "${2:-}" ] || { echo "run-item.sh: <issue> must be a number, got '$2'" >&2; exit 1; } ;; esac

item_pass="$1" item_issue="${2:-}" item_reason="${3:-}"
export HARNEST_ITEM=1
[ "$item_pass" = park ] || [ -z "$item_issue" ] || export ONLY_ISSUES="$item_issue"
if [ -n "$item_queue" ]; then export HARNEST_ITEM_QUEUE="$item_queue"; else unset HARNEST_ITEM_QUEUE; fi
case "$item_pass" in
  tester) export TESTER_PART=issues ;;
  tester-task) export TESTER_PART=task ;;
  tester-closures) export TESTER_PART=closures ;;
esac
set --
# shellcheck source=../run-loop.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/run-loop.sh"
# shellcheck disable=SC2034  # cycle is read by run-loop.sh (run_agent)
case "$item_pass" in park|park-external|consolidation|housekeeping|labels) cycle=item; : > "$LAST_SESSION" ;; *) item_init ;; esac

# unpark_pass reads DW_FROZEN: HARNEST_DW_FROZEN from the driver, else dw_frozen
# (without it a pass with no session would see 0, and unpark mid-freeze).
item_frozen() { case "${HARNEST_DW_FROZEN:-}" in 0|1) DW_FROZEN="$HARNEST_DW_FROZEN" ;; *) if dw_frozen; then DW_FROZEN=1; else DW_FROZEN=0; fi ;; esac; }
item_fail() { echo "[item] $item_pass${item_issue:+ #$item_issue} failed (driver error)" | tee -a "$LOOP_LOG" >&2; exit 1; }
case "$item_pass" in
  implementer|triage) implementer_pass || item_fail ;;
  lead) lead_pass || item_fail ;;
  features) features_pass || item_fail ;;
  tester|tester-task|tester-closures)
    tester_pass || item_fail
    co_author_for "$TESTER_PROVIDER" "$(resolved_model "tester$TARGET_SUFFIX$PROMPT_TAG" "$TESTER_MODEL")"
    item_what="$item_pass"; [ -z "$item_issue" ] || item_what="#$item_issue"
    item_land_note "regression: tester added case ($item_what)" ;;
  reviewer-arch) reviewer_pass arch || item_fail ;;
  reviewer-docs) reviewer_pass docs || item_fail ;;
  delegate) delegate_pass || item_fail ;;
  delegate-suite) delegate_suite_pass || item_fail ;;
  curator) curator_pass || item_fail ;;
  park) park_issue "$item_issue" "$item_reason" || item_fail ;;
  park-external) park_external_issues || item_fail ;;
  unpark) item_frozen; unpark_pass || item_fail ;;
  consolidation) consolidation_pass || item_fail ;;
  housekeeping)
    item_frozen
    hk_rc=0
    park_external_issues || hk_rc=1
    unpark_pass || hk_rc=1
    consolidation_pass || hk_rc=1
    [ "$hk_rc" = 0 ] || item_fail ;;
  labels) ensure_loop_labels ;;
esac
exit 0
