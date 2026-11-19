#!/usr/bin/env bash
# lib/run-item.sh <pass> [<issue> [<reason>]]
# One pass of run-loop.sh for one issue, as a child of the Python scheduler
# (harness/drivers/loop.py, R17). It sources run-loop.sh in item mode
# (HARNEST_ITEM=1): no driver lock, no deploy, no suite commit, no cycle loop.
# The scheduler holds the lock, owns every deploy, lands suite edits from the
# session's tree (harness/suite_tree.py) and reads the board for the outcome.
#
# Passes (run-loop.sh's functions, narrowed to <issue> by ONLY_ISSUES):
#   implementer      triage/fix (implementer_pass)
#   triage           the same pass: triage runs when the issue is stranded
#   lead             build or close-out (lead_pass)
#   features         design or decompose (run-features.sh, via features_pass)
#   tester           spec, verify, handoff or answer (tester_pass, TESTER_PART=issues)
#   tester-task      the standing task, now (TESTER_PART=task)
#   tester-closures  the closures session (TESTER_PART=closures)
#   reviewer-arch    architecture review (reviewer_pass arch)
#   reviewer-docs    docs review (reviewer_pass docs)
#   curator          one suite-change request on HARNESS_REPO (curator_pass)
#   park             park_issue <issue> <reason>: with Don, for the driver
#   park-external    park_external_issues
#   unpark           unpark_pass
#   consolidation    consolidation_pass
#   labels           the claim and backend labels the loop makes at startup
#
# Environment, from the scheduler: DW_TARGET, ONLY_ISSUES (set from <issue>
# here when given), HARNEST_LAST_SESSION (logs/.last-session.item.<slot>),
# DEPLOYED_HEAD, HARNEST_DW_FROZEN (0|1, dw_frozen as of the last poll),
# HARNEST_SESSION_TREE and HARNEST_SESSION_BASE (a tester or
# curator item only), and every role knob run-loop.sh reads.
# A tester or curator item leaves <last-session>.land (JSON: msg, kind, name,
# email) for the scheduler's suite_tree.land.
#
# Exit: 0 when a session ran or nothing was ready, 1 on a driver error.

case "${1:-}" in
  implementer|triage|lead|features|tester|tester-task|tester-closures|reviewer-arch|reviewer-docs|curator) ;;
  park) [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "usage: run-item.sh park <issue> <reason>" >&2; exit 1; } ;;
  park-external|unpark|consolidation|labels) ;;
  *) echo "usage: run-item.sh <implementer|triage|lead|features|tester|tester-task|tester-closures|reviewer-arch|reviewer-docs|curator|park|park-external|unpark|consolidation|labels> [<issue>]" >&2; exit 1 ;;
esac
case "$1" in
  tester|curator|implementer|lead|reviewer-arch|reviewer-docs|park)
    [ -n "${2:-}" ] || { echo "run-item.sh: $1 is a per-issue pass and needs an <issue>" >&2; exit 1; } ;;
esac
[ -n "${HARNEST_LAST_SESSION:-}" ] \
  || { echo "run-item.sh: HARNEST_LAST_SESSION is not set; each item needs its own last-session file (logs/.last-session.item.<slot>)" >&2; exit 1; }
case "${2:-}" in ''|*[!0-9]*) [ -z "${2:-}" ] || { echo "run-item.sh: <issue> must be a number, got '$2'" >&2; exit 1; } ;; esac

item_pass="$1" item_issue="${2:-}" item_reason="${3:-}"
export HARNEST_ITEM=1
[ "$item_pass" = park ] || [ -z "$item_issue" ] || export ONLY_ISSUES="$item_issue"
case "$item_pass" in
  tester) export TESTER_PART=issues ;;
  tester-task) export TESTER_PART=task ;;
  tester-closures) export TESTER_PART=closures ;;
esac
set --
# shellcheck source=../run-loop.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/run-loop.sh"
# shellcheck disable=SC2034  # cycle is read by run-loop.sh (run_agent)
case "$item_pass" in park|park-external|consolidation|labels) cycle=item; : > "$LAST_SESSION" ;; *) item_init ;; esac

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
  curator) curator_pass || item_fail ;;
  park) park_issue "$item_issue" "$item_reason" || item_fail ;;
  park-external) park_external_issues || item_fail ;;
  unpark) unpark_pass || item_fail ;;
  consolidation) consolidation_pass || item_fail ;;
  labels) ensure_loop_labels ;;
esac
exit 0
