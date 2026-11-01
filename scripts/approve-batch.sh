#!/usr/bin/env bash
# Approve a batch of plan reviews in one go (roadmap R15). The digest lists
# the plans the lead put in the batch lane (`lane:batch`: no question of a
# kind Don decides, no new MCP/REST/syntax surface, no dependency or
# download) and prints this command with their numbers.
#
#   scripts/approve-batch.sh 1059 1060 1061    # shows each, asks once
#   scripts/approve-batch.sh -y 1059 1060      # no prompt
#
# Don runs this, as himself: it is his approval, which no agent can give.
# Each issue must still be owner:don + status:plan-review + lane:batch, or it
# is skipped untouched (a plan re-filed or pulled out of the lane since the
# digest was written). Each approved issue gets a comment naming the plan
# version and goes to owner:lead + status:plan-approved; a line per approval
# goes to logs/approvals.jsonl, which is how the lanes get measured.
# Exit 1 if any issue was skipped.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
LOGS="${LOGS:-$REPO/logs}"

yes=0
[ "${1:-}" = -y ] && { yes=1; shift; }
[ $# -gt 0 ] || { echo "usage: $0 [-y] <issue>..." >&2; exit 2; }

ready=() versions=() skipped=0
for n in "$@"; do
  n="${n#\#}"
  view="$(gh issue view "$n" --repo "$TICKET_REPO" --json number,title,labels,comments)" \
    || { echo "#$n: could not read it, skipped" >&2; skipped=$((skipped + 1)); continue; }
  labels="$(jq -r '[.labels[].name] | join(",")' <<<"$view")"
  if ! jq -e '[.labels[].name] as $l | all("owner:don", "status:plan-review", "lane:batch"; IN($l[]))' <<<"$view" >/dev/null; then
    echo "#$n: not a batch plan ($labels), skipped"; skipped=$((skipped + 1)); continue
  fi
  v="$(jq -r '[.comments[].body | select(startswith("<!-- harnest:plan v")) | select(test("^[^\n]*draft:") | not)
               | capture("^<!-- harnest:plan v(?<v>[0-9]+)").v] | last // ""' <<<"$view")"
  [ -n "$v" ] || { echo "#$n: no posted plan, skipped"; skipped=$((skipped + 1)); continue; }
  echo "#$n plan v$v: $(jq -r .title <<<"$view")"
  ready+=("$n"); versions+=("$v")
done

if [ "${#ready[@]}" -gt 0 ] && [ "$yes" = 0 ]; then
  printf 'approve these %s? [y/N] ' "${#ready[@]}"
  read -r answer || answer=""
  case "$answer" in y|Y|yes) ;; *) echo "nothing approved"; exit 1 ;; esac
fi

mkdir -p "$LOGS"
body="$(mktemp)"; trap 'rm -f "$body"' EXIT
i=0
while [ "$i" -lt "${#ready[@]}" ]; do
  n="${ready[$i]}" v="${versions[$i]}"
  printf 'Approved with the batch: plan v%s, its defaults.\n' "$v" > "$body"
  gh issue comment "$n" --repo "$TICKET_REPO" --body-file "$body" >/dev/null
  gh issue edit "$n" --repo "$TICKET_REPO" --remove-label owner:don,status:plan-review,lane:batch \
    --add-label owner:lead,status:plan-approved >/dev/null
  jq -cn --arg at "$(date -u +%FT%TZ)" --argjson issue "$n" --argjson plan "$v" \
    '{at: $at, issue: $issue, plan: $plan, lane: "batch"}' >> "$LOGS/approvals.jsonl"
  echo "#$n approved"
  i=$((i + 1))
done
[ "$skipped" -eq 0 ]
