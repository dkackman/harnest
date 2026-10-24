#!/usr/bin/env bash
# case-text.sh <suite-file> <id>...
# The text a chunk session is handed in place of reading the suite: the
# suite's Fixtures section, then each named case's block, in that order.
# The Python driver calls harness.suite.case_text directly; run-regression.sh
# calls this, so both hand the agent the same bytes.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONPATH="$here${PYTHONPATH:+:$PYTHONPATH}" exec python3 -m harness.suite case-text "$@"
