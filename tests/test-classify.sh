#!/usr/bin/env bash
# lib/classify.jq over each fixture board in classify-cases.json: every
# issue's queue must match the expected one. The fixtures are snapshots in
# the shape issue_snapshot (providers.sh) builds; one board per state of
# the protocol, including each of Don's hand-backs. A board's optional
# expect_reason checks reasons as well.
. "$(dirname "$0")/lib.sh"
while IFS= read -r c; do
  name="$(jq -r .name <<<"$c")"
  got="$(jq '.input' <<<"$c" | jq -c -f "$HARNEST/lib/classify.jq" | jq -s 'map({key: (.number | tostring), value: .}) | from_entries')"
  while IFS=$'\t' read -r n want; do
    eq "[$name] #$n" "$want" "$(jq -r --arg n "$n" '.[$n].queue // "missing"' <<<"$got")"
  done < <(jq -r '.expect | to_entries[] | "\(.key)\t\(.value)"' <<<"$c")
  # expect_reason, where a board has one: the reason too, for the states a
  # driver reads by reason (a deferral in the don queue)
  while IFS=$'\t' read -r n want; do
    eq "[$name] #$n reason" "$want" "$(jq -r --arg n "$n" '.[$n].reason // "missing"' <<<"$got")"
  done < <(jq -r '(.expect_reason // {}) | to_entries[] | "\(.key)\t\(.value)"' <<<"$c")
done < <(jq -c '.[]' "$HARNEST/tests/classify-cases.json")
finish
