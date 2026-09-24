#!/usr/bin/env bash
# Runs lib/classify.jq over each fixture in classify-cases.json and compares
# every issue's queue with the expected one. No network: the fixtures are
# snapshots in the shape issue_snapshot (providers.sh) builds.
#
#   tests/test-classify.sh          # exit 0 when every expectation holds
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0; total=0
while IFS= read -r c; do
  name="$(printf '%s' "$c" | jq -r .name)"
  got="$(printf '%s' "$c" | jq '.input' | jq -c -f "$here/../lib/classify.jq" | jq -s 'map({key: (.number | tostring), value: .}) | from_entries')"
  while IFS=$'\t' read -r n want; do
    total=$((total + 1))
    have="$(printf '%s' "$got" | jq -r --arg n "$n" '.[$n].queue // "missing"')"
    if [ "$have" != "$want" ]; then
      fail=$((fail + 1))
      echo "FAIL [$name] #$n: want $want, got $have ($(printf '%s' "$got" | jq -r --arg n "$n" '.[$n].reason // ""'))"
    fi
  done < <(printf '%s' "$c" | jq -r '.expect | to_entries[] | "\(.key)\t\(.value)"')
done < <(jq -c '.[]' "$here/classify-cases.json")
echo "$((total - fail))/$total expectations hold"
[ "$fail" -eq 0 ]
