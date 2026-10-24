#!/usr/bin/env bash
# record-results.sh <results-dir> <server> <level> <session-label> <head> <model> [case...] < $LAST_SESSION
# Appends one line per case to <results-dir>/<case>.jsonl from a session's
# rendered log: its REGRESSION-RESULT / REGRESSION-SKIP lines, and for a
# case it was handed but never answered, unreported (or not run, when the
# session died). harness/results.py; format in regression-results/README.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONPATH="$here${PYTHONPATH:+:$PYTHONPATH}" exec python3 -m harness.results record "$@"
