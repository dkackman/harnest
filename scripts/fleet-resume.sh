#!/bin/bash
# Re-run the cases a fleet run left without an answer (a session died, the
# login expired, budget or turns ran out): every case whose outcome is not
# pass, fail or skip in that run's record. Answered cases are not re-run;
# REGRESSION_CASES still pulls each remaining case's dependency group in.
#
#   scripts/fleet-resume.sh                      # the newest run in logs/fleet/runs/
#   scripts/fleet-resume.sh logs/fleet/runs/20261127-110024.json
#   scripts/fleet-resume.sh --print [run.json]   # list the cases; run nothing
#
# The environment passes through to the fleet (FLEET_SERVERS and the rest).
# Read from logs/fleet/runs/, not state.json: the new run rewrites state.json.
set -euo pipefail
cd "$(dirname "$0")/.."

print_only=0
if [ "${1-}" = "--print" ]; then print_only=1; shift; fi

run="${1-}"
if [ -z "$run" ]; then
  run="$(ls -1 logs/fleet/runs/*.json 2>/dev/null | tail -1)"
fi
[ -f "$run" ] || { echo "fleet-resume: no run record ${run:-in logs/fleet/runs/}" >&2; exit 2; }

cases="$(python3 - "$run" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
left = [c for c, v in s["cases"].items() if v.get("outcome") not in ("pass", "fail", "skip")]
print(" ".join(sorted(left)))
EOF
)"

n=$(echo "$cases" | wc -w | tr -d ' ')
if [ "$n" -eq 0 ]; then echo "fleet-resume: every case in $run has an answer"; exit 0; fi
echo "fleet-resume: $n case(s) without an answer in $run" >&2

if [ "$print_only" -eq 1 ]; then echo "$cases"; exit 0; fi
REGRESSION_CASES="$cases" exec python3 -m harness.drivers.fleet all
