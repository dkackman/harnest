#!/usr/bin/env bash
# lib/board.sh [<query>] <target>
# The board as the Python loop driver (harness/drivers/loop.py, R17) reads
# it, through the bash that already defines it, so there is one copy of
# each rule. <target> is a loop server (DW_TARGET: lem, mini-ai).
#
#   board.sh <target>           classify_issues for <target>, one line per
#                               open issue: number, queue, parent (or -),
#                               reason, holder, tab-separated. holder is the
#                               server whose target:* claim (its own, else
#                               its parent's) holds the issue, lem's when
#                               both claim it (classify.jq's holder_of), or -
#   board.sh status <target>    status_board: one line per open issue
#   board.sh drain <target>     drain_left: work, away, don, done or unknown
#   board.sh closures <target>  pending_closures, one number per line
#   board.sh curator <target>   curator_requests, one number per line
#   board.sh freeze <target>    release_freeze: "#<n> <title>", UNKNOWN, or nothing
#   board.sh frozen <target>    dw_frozen as 1 or 0
#   board.sh hk <target> [lead] the driver's once-a-poll reads in one go, a
#                               line each, tab-separated: "frozen 0|1",
#                               "freeze <release_freeze>", "closures <n>...";
#                               with lead also "curator <n>..." and a
#                               "status <line>" per status_board line (or
#                               "status-unreadable")
#
# Exit 1 when the board can't be read (rows and status), or on a bad call.
# The plain rows need providers.sh only; the other queries source
# run-loop.sh in item mode (no lock, no deploy, no session), the way
# lib/run-item.sh does, because their rules live there.

lead=""
case $# in
  1) query=rows target="$1" ;;
  2) query="$1" target="$2" ;;
  3) query="$1" target="$2" lead="$3"; [ "$query $lead" = "hk lead" ] || { echo "board.sh: only hk takes a third argument (lead)" >&2; exit 1; } ;;
  *) echo "usage: board.sh [status|drain|closures|curator|freeze|frozen|hk] <target> [lead]" >&2; exit 1 ;;
esac
case "$query" in rows|status|drain|closures|curator|freeze|frozen|hk) ;; *) echo "board.sh: unknown query '$query'" >&2; exit 1 ;; esac
[ -n "$target" ] || { echo "board.sh: no target" >&2; exit 1; }
export DW_TARGET="$target"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$query" = rows ]; then
  set -uo pipefail
  REPO="$here"
  LOGS="$REPO/logs"
  TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
  TICKET_OWNER="${TICKET_OWNER:-dkackman}"
  ONLY_ISSUES=""   # the driver narrows by ONLY_ISSUES itself
  unset HARNEST_ITEM_QUEUE
  mkdir -p "$LOGS"
  # shellcheck source=../providers.sh
  . "$REPO/providers.sh"
  resolve_target || exit 1
  rows="$(classify_issues)" || exit 1
  # the same snapshot (issue_snapshot caches it for this process)
  holders="$(issue_snapshot | jq -r '
    (.issues | map({key: (.number | tostring), value: [.labels[].name | select(startswith("target:")) | ltrimstr("target:")]})
      | from_entries) as $c
    | .issues[] | . as $i
    | (($c[$i.number | tostring] // []) | if length > 0 then . else ($c[($i.parent.number // 0) | tostring] // []) end) as $t
    | [(.number | tostring), (if $t == [] then "-" elif ($t | index("lem")) != null then "lem" else $t[0] end)] | @tsv')" || exit 1
  [ -n "$rows" ] || exit 0
  awk -F'\t' -v OFS='\t' 'NR == FNR { hold[$1] = $2; next } { print $1, $2, $3, $4, (($1 in hold) ? hold[$1] : "-") }' \
    <(printf '%s\n' "$holders") <(printf '%s\n' "$rows")
  exit 0
fi

# The rules that live in run-loop.sh: source it in item mode, with a
# last-session file of its own (item mode wants one; no session runs).
export HARNEST_ITEM=1 HARNEST_LAST_SESSION="logs/.last-session.board.$target"
unset HARNEST_SESSION_TREE HARNEST_SESSION_BASE HARNEST_ITEM_QUEUE
set --
# shellcheck source=../run-loop.sh
. "$here/run-loop.sh"
# shellcheck disable=SC2034  # read by run-loop.sh
cycle=board
case "${HARNEST_DW_FROZEN:-}" in 0|1) DW_FROZEN="$HARNEST_DW_FROZEN" ;; *) if dw_frozen; then DW_FROZEN=1; else DW_FROZEN=0; fi ;; esac
case "$query" in
  status) out="$(status_board)"; [ -n "$out" ] || { gh issue list --repo "$TICKET_REPO" --state open --limit 1 --json number >/dev/null 2>&1 || exit 1; }
          [ -z "$out" ] || printf '%s\n' "$out" ;;
  drain) drain_left ;;
  closures) pending_closures || true ;;
  curator) curator_requests || true ;;
  freeze) release_freeze ;;
  frozen) echo "$DW_FROZEN" ;;
  hk)
    printf 'frozen\t%s\n' "$DW_FROZEN"
    printf 'freeze\t%s\n' "$(release_freeze)"
    printf 'closures\t%s\n' "$(pending_closures | tr '\n' ' ')"
    if [ -n "$lead" ]; then
      printf 'curator\t%s\n' "$(curator_requests | tr '\n' ' ')"
      printf 'delegate-suite\t%s\n' "$(delegate_suite_requests | tr '\n' ' ')"
      out="$(status_board)"
      if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/status\t/'
      elif gh issue list --repo "$TICKET_REPO" --state open --limit 1 --json number >/dev/null 2>&1; then :
      else echo status-unreadable; fi
    fi ;;
esac
exit 0
