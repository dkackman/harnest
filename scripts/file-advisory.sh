#!/usr/bin/env bash
# File a security finding privately, as a draft GitHub security advisory on
# the ticket repo (roadmap R14 item 3). A draft is visible only to the repo's
# admins and the advisory's collaborators - never on the public tracker,
# where a finding would publish the exploit path along with it.
#
#   scripts/file-advisory.sh --summary "SE-F023: ..." --description-file f.md --severity high
#   scripts/file-advisory.sh --list        # open drafts: ghsa id, severity, summary
#
# A draft whose summary matches exactly is not filed twice: the description
# gets a dated "seen again" section appended instead, so a regression run
# that meets the same hole every night keeps one advisory current. Prints
# the advisory's URL. Severity: low | medium | high | critical.
#
# Agents run this (the tester, the regression agent, the implementer) and so
# does run-release.sh. The worst an agent can do with it is file a private
# draft Don has to close. It never publishes, and never touches an issue.
set -euo pipefail

TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
ADVISORY_PACKAGE="${ADVISORY_PACKAGE:-diffusers-workflow}"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"

summary="" description_file="" severity="" list=0
while [ $# -gt 0 ]; do
  case "$1" in
    --summary) summary="${2:-}"; shift 2 ;;
    --description-file) description_file="${2:-}"; shift 2 ;;
    --severity) severity="${2:-}"; shift 2 ;;
    --list) list=1; shift ;;
    *) echo "usage: $0 --summary <text> --description-file <file> --severity low|medium|high|critical | --list" >&2; exit 2 ;;
  esac
done

if [ "$list" = 1 ]; then
  gh api "repos/$TICKET_REPO/security-advisories?state=draft&per_page=100" \
    --jq '.[] | "\(.ghsa_id)\t\(.severity // "-")\t\(.summary)"'
  exit 0
fi

[ -n "$summary" ] && [ -r "$description_file" ] || { echo "file-advisory: --summary and a readable --description-file are required" >&2; exit 2; }
case "$severity" in low|medium|high|critical) ;; *) echo "file-advisory: --severity must be low, medium, high or critical" >&2; exit 2 ;; esac

existing="$(gh api "repos/$TICKET_REPO/security-advisories?state=draft&per_page=100" \
  --jq ".[] | select(.summary == $(jq -Rn --arg s "$summary" '$s')) | .ghsa_id" | head -n 1)"

if [ -n "$existing" ]; then
  current="$(gh api "repos/$TICKET_REPO/security-advisories/$existing" --jq .description)"
  jq -n --arg d "$current

## Seen again, $(date -u '+%Y-%m-%d %H:%M UTC')

$(cat "$description_file")" '{description: $d}' \
    | gh api -X PATCH "repos/$TICKET_REPO/security-advisories/$existing" --input - --jq .html_url
  exit 0
fi

# The versions it affects: everything up to the latest release, which is
# what a draft can honestly claim before anyone has bisected it
latest="$(git -C "$SOURCE_DIR" describe --tags --abbrev=0 origin/master 2>/dev/null || true)"
jq -n --arg summary "$summary" --arg description "$(cat "$description_file")" --arg severity "$severity" \
      --arg package "$ADVISORY_PACKAGE" --arg range "${latest:+<= ${latest#v}}" '
  {summary: $summary, description: $description, severity: $severity,
   vulnerabilities: [{package: {ecosystem: "pip", name: $package},
                      vulnerable_version_range: (if $range == "" then null else $range end)}]}' \
  | gh api -X POST "repos/$TICKET_REPO/security-advisories" --input - --jq .html_url
