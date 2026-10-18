#!/usr/bin/env bash
# The harness/ package's unit tests (tests/py, stdlib unittest, R8): each
# module against the bash it replaces, while that bash still exists.
. "$(dirname "$0")/lib.sh"
out="$(cd "$HARNEST" && python3 -m unittest discover -s tests/py -t . 2>&1)"; rc=$?
eq  "python unit tests pass" 0 "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out" | tail -40
finish
