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
  46 wait - building \
  47 wait - "release freeze (#40): not a release-blocker (tester:verify after it)" \
  48 wait 46 "release freeze (#40): not a release-blocker (lead:build after it)" \
  50 wait - building \
  49 wait - "release freeze (#40): not a release-blocker (reviewer:docs after it)")"
problems="$(printf '%s\n' "$board" | release_board_problems 40 "46 62")"
eq "board: six problems" 6 "$(printf '%s\n' "$problems" | grep -c .)"
has "board: a frozen fix awaiting verification is merged work" "#47 is merged but unverified (tester:verify" "$problems"
eq "board: a held stage is not (its feature is)" "" "$(printf '%s\n' "$problems" | grep '#48 ' || true)"
eq "board: a feature with no stage closed is not" "" "$(printf '%s\n' "$problems" | grep '#50 ' || true)"
has "board: a frozen docs review" "#49 is merged but unverified (reviewer:docs" "$problems"
has "board: a verify in flight" "#42 waits on verification" "$problems"
has "board: stranded" "#43 is stranded" "$problems"
has "board: an open blocker" "#44 is open work in implementer:fix" "$problems"
has "board: a feature mid-build" "#46 is a feature with stages merged" "$problems"
eq "board: held and parked issues are not problems" "" "$(printf '%s\n' "$board" | grep -E '^4[015]' | release_board_problems 40)"

# --- commits: an open issue develop carries commits for ships unfinished
log="$(printf '%s\n' \
  "a1 fix(tasks): #70 - withdraw the upscaler (#71) for 0.9.0" \
  "b2 fix(result): #71 - a missing property is an error" \
  "c3 feat(tasks): #71 - the upscaler" \
  "d4 feat(templates): #72 - expose limit" \
  "e5 fix(mcp): #73 - already flagged" \
  "f6 fix: #74 - closed and verified" \
  "g7 docs: mention #75 in passing")"
unfinished="$(printf '%s\n' "$log" | release_open_with_commits "70 71 72 73 75" "73")"
eq "commits: one line per unfinished open issue" 2 "$(printf '%s\n' "$unfinished" | grep -c .)"
has "commits: the withdrawal itself, until it is verified" "#70 is open, but develop carries its commits" "$unfinished"
has "commits: a stage merged under an old plan" "#72 is open, but develop carries its commits (latest d4 feat(templates): #72" "$unfinished"
eq "commits: a withdrawn issue is not" "" "$(printf '%s\n' "$unfinished" | grep '#71 ' || true)"
eq "commits: an issue named only in passing is not" "" "$(printf '%s\n' "$unfinished" | grep '#75 ' || true)"
eq "commits: without its withdrawal it is" "#71" "$(printf '%s\n' "$log" | grep -v withdraw | release_open_with_commits "71" | cut -d' ' -f1)"

# --- waivers: Don's accepted problems, honoured by every later check
wv="$(comments "$(release_waive_marker 474)$(printf '\n')$(release_waive_marker 497)" "prose naming harnest:release-waive 12" | release_waivers)"
eq "waivers: parsed from their markers only" "474 497" "$wv"
kept="$(printf '%s\n' "#474 is open, but develop carries its commits" "#497 is a stage being built" "#50 waits on verification" "lem runs develop @ 0000000" | release_drop_waived "$wv")"
eq "waivers: waived issues dropped, the rest kept" "#50 waits on verification|lem runs develop @ 0000000" "$(printf '%s\n' "$kept" | paste -sd'|' -)"
eq "waivers: #4740 is not #474" "#4740 x" "$(echo "#4740 x" | release_drop_waived 474)"

# --- carry: which commits a gate may be carried across
tab() { printf '%s\t%s\t%s\t%s\n' "$@"; }
notes="$(tab aaaaaaaaaaaa 1 "docs(release): 0.9.0 notes" docs/RELEASING.md)"
fix="$(tab bbbbbbbbbbbb 1 "fix(mcp): #521 - no server path in delete replies" "dw/server/app.py tests/test_app.py")"
merge="$(tab cccccccccccc 2 "Merge branch 'fix/521' into develop" "")"
other="$(tab dddddddddddd 1 "feat(tasks): #600 - something new" dw/tasks.py)"
wide="$(tab eeeeeeeeeeee 1 "docs: notes and a guide" "docs/RELEASING.md docs/guide.md")"
ok  "carry: the notes merge, for regression" release_carry_ok regression "521" <<<"$notes"
ok  "carry: a verified blocker's fix and its merge, for review" release_carry_ok review "521" <<<"$(printf '%s\n' "$fix" "$merge" "$notes")"
fails "carry: never regression across a code fix" release_carry_ok regression "521" <<<"$fix"
fails "carry: not across an issue that isn't a verified blocker" release_carry_ok security "521" <<<"$other"
fails "carry: docs beyond the notes are not the notes" release_carry_ok regression "" <<<"$wide"
eq  "carry: names what stopped it" "dddddddddd feat(tasks): #600 - something new" \
  "$(printf '%s\n' "$fix" "$other" | release_carry_ok review "521" || true)"
eq  "carry: a carried marker counts as good" "check ci preflight regression review security" \
  "$(printf 'review %s carried\nsecurity %s carried\n' $A $A | release_missing_gates $B)"
ok  "carry: carried is ok on its commit" release_gate_ok review $A <<<"review $A carried"

# --- closing comments: the owner's last comment per issue, for the notes
cc="$(jq -n '[{number: 5, title: "a bug", comments: [{author: {login: "dkackman"}, body: "first"}, {author: {login: "stranger"}, body: "spam"}, {author: {login: "dkackman"}, body: "Verified: it ships X."}]},
             {number: 6, title: "quiet", comments: []},
             {number: 7, title: "long", comments: [{author: {login: "dkackman"}, body: ("y" * 2000)}]}]' | release_closing_comments dkackman)"
has "closing: the owner's last comment" "## #5 a bug

Verified: it ships X." "$cc"
eq  "closing: never another login's" "" "$(printf '%s' "$cc" | grep spam || true)"
has "closing: says when there is none" "(no closing comment)" "$cc"
has "closing: cuts a long one" "[...]" "$cc"

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
