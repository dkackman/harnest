#!/usr/bin/env bash
# The curator's weekly consolidation cadence (lib/consolidation.py) on a
# fixture tree whose scripts/arch_report.py prints a canned report, in the
# table format dw's real one prints. Never the real dw checkout.
. "$(dirname "$0")/lib.sh"
c="$HARNEST/lib/consolidation.py"
tree="$T/tree"; mkdir -p "$tree/scripts"; git init -q "$tree"
git -C "$tree" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
state="$T/state.json"
# no open consolidation issue but the one #2's title names; gh issue create prints a URL
stub_gh 'case "$*" in "issue list"*) echo "consolidation: dw/e.py and dw/f.py change together" ;;
  "issue create"*) echo "https://github.com/o/r/issues/$(( $(grep -c "issue create" "$GH_CALLS") + 40 ))" ;; *) exit 1 ;; esac'
# report <coupling rows> <hotspot rows>: the canned report the fixture prints
report() {
  cat > "$tree/scripts/arch_report.py" <<EOF
print("""#### Metrics

| Metric (lower is better) | HEAD (\`HEAD\`) |
| --- | --- |
| Engine + MCP modules | 165 |

#### Change coupling at HEAD (commits since 2026-08-01)

| Shared commits | Degree % | File | File |
| --- | --- | --- | --- |
$1

#### Hotspots at HEAD (churn x total complexity)

| Score | Commits | Complexity | File |
| --- | --- | --- | --- |
$2
""")
EOF
}
run() { python3 "$c" run --tree "$tree" --python python3 --state "$state" --repo o/r; }
age() { python3 - "$state" "$1" <<'PY'  # age <days>: last week's run, N days ago
import json, sys, time
s = json.load(open(sys.argv[1])); s["ran_at"] = int(time.time()) - int(float(sys.argv[2]) * 86400); json.dump(s, open(sys.argv[1], "w"))
PY
}
quiet_pairs='| 12 | 80 | dw/a.py | dw/b.py |
| 9 | 60 | dw/c.py | dw/d.py |
| 6 | 50 | dw/e.py | dw/f.py |'
hot='| 400 | 20 | 20 | dw/a.py |
| 90 | 9 | 10 | dw/c.py |'

# no report script on develop: the cadence is off, silently
rm -f "$tree/scripts/arch_report.py"
eq "off without arch_report.py: no output" "" "$(run)"
eq "  and no state" "absent" "$([ -e "$state" ] && echo present || echo absent)"

# the first report is only a baseline
report "$quiet_pairs" "$hot"
has "first report: kept as the baseline" "kept as next week's baseline, nothing filed" "$(run)"
eq  "  nothing filed" 0 "$(grep -c 'issue create' "$GH_CALLS")"
eq  "  the tables are kept" "3 2" "$(jq -r '"\(.coupling | length) \(.hotspots | length)"' "$state")"

# not due yet: nothing runs
age 3
eq "three days later: not due, no output" "" "$(run)"

# a quiet week: the same tables, nothing moved, nothing filed
age 8
has "a quiet week: says nothing moved" "0 pair(s) moved, filed nothing" "$(run)"
eq  "  nothing filed" 0 "$(grep -c 'issue create' "$GH_CALLS")"
# below the bar: a pair whose shared commits rose by four
report '| 16 | 82 | dw/a.py | dw/b.py |
| 9 | 60 | dw/c.py | dw/d.py |
| 6 | 50 | dw/e.py | dw/f.py |' "$hot"
age 8
has "a rise of four: nothing filed" "0 pair(s) moved, filed nothing" "$(run)"
eq  "  nothing filed" 0 "$(grep -c 'issue create' "$GH_CALLS")"

# a week that moved: a rise of five, two new pairs, one already open, and
# more than three candidates in all
report '| 21 | 85 | dw/a.py | dw/b.py |
| 9 | 60 | dw/c.py | dw/d.py |
| 8 | 55 | dw/e.py | dw/f.py |
| 7 | 70 | dw/g.py | dw/h.py |
| 6 | 65 | dw/i.py | dw/j.py |
| 5 | 40 | dw/k.py | dw/l.py |' "$hot"
python3 - "$state" <<'PY'  # last week also lacked e/f, so it is "new" but already has an open issue
import json, sys
s = json.load(open(sys.argv[1])); s["coupling"] = [r for r in s["coupling"] if r[2] != "dw/e.py"]; json.dump(s, open(sys.argv[1], "w"))
PY
age 8
out="$(run)"
has "a week that moved: at most three filed" "5 pair(s) moved, filed #41, #42, #43; 1 already open" "$out"
eq  "  three issues" 3 "$(grep -c 'issue create' "$GH_CALLS")"
calls="$(cat "$GH_CALLS")"
has "  the rise comes first" "dw/a.py and dw/b.py change together" "$(grep 'issue create' "$GH_CALLS" | head -1)"
has "  labelled consolidation and owner:don" "change together --label consolidation --label owner:don" "$calls"
has "  with both weeks' numbers" "| Shared commits | 16 | 21 |" "$calls"
has "  and the reason" "shared commits rose by 5" "$calls"
has "  and hotspots for each file" "score 400 (20 commits x complexity 20)" "$calls"
has "  new pairs next, largest first" "dw/g.py and dw/h.py" "$(grep 'issue create' "$GH_CALLS" | sed -n 2p)"
has "  a new pair says so" "| Shared commits | not in the top ten | 7 |" "$calls"
fails "  the pair with an open issue is not filed again" grep -q 'issue create.*dw/e.py and dw/f.py' "$GH_CALLS"

# a report that fails is retried a day later, not every cycle
printf 'import sys; sys.exit("grimp: boom")\n' > "$tree/scripts/arch_report.py"
age 8
has "a failed report: logged" "arch_report.py failed (exit 1), retrying in a day: grimp: boom" "$(run)"
eq  "  not retried the same day" "" "$(run)"
finish
