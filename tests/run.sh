#!/usr/bin/env bash
# Runs every tests/test-*.sh. Offline: gh, ssh and claude are stubbed where
# a test needs them, and nothing touches GitHub, lem or the account.
#
#   tests/run.sh              # all
#   tests/run.sh guard        # only test-guard.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for t in "$here"/test-${1:-*}.sh; do
  bash "$t" || failed=$((failed + 1))
done
[ "$failed" -eq 0 ] && echo "all test files passed" || { echo "$failed test file(s) failed"; exit 1; }
