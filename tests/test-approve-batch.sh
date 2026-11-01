#!/usr/bin/env bash
# scripts/approve-batch.sh (roadmap R15) over a fake-gh board: it approves
# only issues still in the batch lane (owner:don + status:plan-review +
# lane:batch), and leaves every other issue it is given untouched.
. "$(dirname "$0")/lib.sh"
ln -s "$HARNEST/tests/fake-gh.py" "$T/bin/gh"
cat > "$T/board.json" <<'EOF'
{"o/r": [
 {"number": 1, "state": "OPEN", "title": "batch plan",
  "labels": [{"name": "feature"}, {"name": "owner:don"}, {"name": "status:plan-review"}, {"name": "lane:batch"}],
  "comments": [{"author": {"login": "dkackman"}, "body": "<!-- harnest:plan v3 -->\n# Plan v3", "createdAt": "2026-11-01T00:00:00Z"}]},
 {"number": 2, "state": "OPEN", "title": "blocking plan",
  "labels": [{"name": "feature"}, {"name": "owner:don"}, {"name": "status:plan-review"}],
  "comments": []},
 {"number": 3, "state": "OPEN", "title": "with the lead",
  "labels": [{"name": "feature"}, {"name": "owner:lead"}, {"name": "lane:batch"}],
  "comments": []}
]}
EOF
labels_of() { jq -r --arg n "$1" '.["o/r"][] | select((.number|tostring) == $n) | [.labels[].name] | sort | join(",")' "$T/board.json"; }
before2="$(labels_of 2)"; before3="$(labels_of 3)"

out="$(env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r "$HARNEST/scripts/approve-batch.sh" -y 1 2 3 2>&1)"; rc=$?
eq  "a refused issue makes the exit non-zero" 1 "$rc"
eq  "#1 approved: owner:lead + plan-approved, out of the lane" "feature,owner:lead,status:plan-approved" "$(labels_of 1)"
has "#1 carries the batch approval, naming the plan version" "Approved with the batch: plan v3, its defaults." \
    "$(jq -r '.["o/r"][0].comments[-1].body' "$T/board.json")"
eq  "#2 (not in the lane) untouched" "$before2" "$(labels_of 2)"
eq  "#3 (not Don's) untouched" "$before3" "$(labels_of 3)"
eq  "both refusals are reported" 2 "$(grep -c 'skipped' <<<"$out")"
eq  "one approval recorded" 1 "$(wc -l < "$LOGS/approvals.jsonl" | tr -d ' ')"
eq  "the record names the issue, plan and lane" "1 3 batch" "$(jq -r '"\(.issue) \(.plan) \(.lane)"' "$LOGS/approvals.jsonl")"

# without -y it asks once, and a no changes nothing
cp "$T/board.json" "$T/board.before"
jq '.["o/r"][1].labels += [{"name": "lane:batch"}]
    | .["o/r"][1].comments += [{"author": {"login": "dkackman"}, "body": "<!-- harnest:plan v1 -->", "createdAt": "2026-11-01T00:00:00Z"}]' \
  "$T/board.before" > "$T/board.json"
snap="$(cat "$T/board.json")"
out="$(printf 'n\n' | env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r "$HARNEST/scripts/approve-batch.sh" 2 2>&1)"
has "it asks before approving" "approve these 1? [y/N]" "$out"
eq  "answering no changes nothing" "$snap" "$(cat "$T/board.json")"
fails "no issue numbers is a usage error" env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r "$HARNEST/scripts/approve-batch.sh" -y
finish
