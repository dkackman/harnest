#!/usr/bin/env bash
# The harness/ package's unit tests (tests/py, stdlib unittest, R8): each
# module against the bash it replaces, while that bash still exists.
. "$(dirname "$0")/lib.sh"
out="$(cd "$HARNEST" && python3 -m unittest discover -s tests/py -t . 2>&1)"; rc=$?
eq  "python unit tests pass" 0 "$rc"
# The tally counts unittest's tests (its "Ran N tests" line), not the one
# assertion above.
n="$(printf '%s\n' "$out" | sed -n 's/^Ran \([0-9][0-9]*\) tests\{0,1\} in .*/\1/p' | tail -n 1)"
[ "$rc" != 0 ] || [ -z "$n" ] || _pass=$((_pass - 1 + n))
[ "$rc" = 0 ] || printf '%s\n' "$out" | tail -40
finish
