#!/usr/bin/env bash
# lib/release.sh, offline: the gate markers and their resume logic, the
# board check, review findings validation, and the notes insertion into
# docs/RELEASING.md. run-release.sh's own stages are in test-drivers.sh
# where the fake gh can carry them.
. "$(dirname "$0")/lib.sh"
. "$HARNEST/lib/release.sh"

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# --- markers: the latest per gate and commit wins, and only that commit counts
comments() { jq -n --args '{comments: [$ARGS.positional[] | {body: .}]}' "$@"; }
results="$(comments \
  "$(release_marker ci $A fail; echo 'CI failed on backend.')" \
  "$(release_marker ci $A pass)" \
  "$(release_marker preflight $A pass)" \
  "$(release_marker regression $B pass)" \
  "an ordinary comment that mentions harnest:release-gate in prose" \
  | release_gate_results)"
eq "markers: one row per gate and commit" 3 "$(printf '%s\n' "$results" | grep -c .)"
eq "markers: the later ci marker wins" "ci $A pass" "$(printf '%s\n' "$results" | grep "^ci ")"
ok "gate ok on its commit" release_gate_ok ci $A <<<"$results"
fails "gate not ok on another commit" release_gate_ok regression $A <<<"$results"
eq "missing: every gate not passed on this commit" "check regression review security" \
  "$(printf '%s\n' "$results" | release_missing_gates $A)"
results2="$(printf '%s\nregression %s accepted\n' "$results" $A)"
eq "missing: an accepted gate counts" "check review security" \
  "$(printf '%s\n' "$results2" | release_missing_gates $A)"

# --- board: only work in flight blocks a release
board="$(printf '%s\t%s\t%s\t%s\n' \
  40 don - "release freeze: Release 0.5.0" \
  41 wait - "release freeze (#40): not a release-blocker (implementer:fix after it)" \
  42 tester:verify - "handed off" \
  43 stranded - "owner labels: none" \
  44 implementer:fix - ready \
  45 don - "status:needs-approval" \
  46 wait - building)"
problems="$(printf '%s\n' "$board" | release_board_problems 40)"
eq "board: four problems" 4 "$(printf '%s\n' "$problems" | grep -c .)"
has "board: a verify in flight" "#42 waits on verification" "$problems"
has "board: stranded" "#43 is stranded" "$problems"
has "board: an open blocker" "#44 is open work in implementer:fix" "$problems"
has "board: a feature mid-build" "#46 is a feature being built" "$problems"
eq "board: held and parked issues are not problems" "" "$(printf '%s\n' "$board" | grep -E '^4[015]' | release_board_problems 40)"

# --- findings: exactly the shape, or the stage fails
f="$T/findings.json"
echo '[{"area":"security","severity":"blocker","security":true,"title":"t","file":"a.py:1","detail":"d"}]' > "$f"
ok "findings: a well-formed list" release_findings_valid "$f"
echo '[]' > "$f"
ok "findings: an empty list is a clean area" release_findings_valid "$f"
echo '[{"area":"x","severity":"major","security":false,"title":"t","file":"","detail":"d"}]' > "$f"
fails "findings: an unknown severity" release_findings_valid "$f"
echo '{"findings": []}' > "$f"
fails "findings: not an array" release_findings_valid "$f"
echo 'not json' > "$f"
fails "findings: not JSON" release_findings_valid "$f"

# --- notes: inserted under Unreleased, a redraft replaces rather than adds
md="$T/RELEASING.md"
printf '# Releasing\n\n## Unreleased\n\nScratch pad.\n\n### 0.4.0\n\nOld notes.\n\n## Cutting\n\nSteps.\n' > "$md"
printf -- '- first draft\n' > "$T/sec"
release_insert_notes "$md" 0.5.0 "$T/sec"
eq "notes: the new section comes before the last release's" "### 0.5.0" "$(grep '^### ' "$md" | head -1)"
eq "notes: the body reads back" "- first draft" "$(release_notes_section "$md" 0.5.0)"
printf -- '- second draft\n' > "$T/sec"
release_insert_notes "$md" 0.5.0 "$T/sec"
eq "notes: a redraft replaces" 1 "$(grep -c '^### 0.5.0' "$md")"
eq "notes: with the new body" "- second draft" "$(release_notes_section "$md" 0.5.0)"
eq "notes: the old release is untouched" "Old notes." "$(release_notes_section "$md" 0.4.0)"
has "notes: the rest of the file is kept" "## Cutting" "$(cat "$md")"
finish
