# tests/lib.sh: a small assert library for the harness's shell tests.
# Sourced by each tests/test-*.sh. No dependencies beyond bash 3.2, jq and
# python3, which the drivers already need.
#
#   ok <name> <command...>        passes when the command exits 0
#   fails <name> <command...>     passes when it exits non-zero
#   eq <name> <want> <got>        passes when the strings are equal
#   has <name> <needle> <hay>     passes when hay contains needle
#   stub_gh <script-body>         puts a fake gh on PATH; the body is bash
#                                 run with the gh arguments in "$@", and
#                                 every call is appended to $GH_CALLS
#   finish                        prints the tally; exit 1 on any failure
#
# Each test file runs in its own temp dir ($T), removed at exit.

set -uo pipefail
HARNEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export LOGS="$T/logs"; mkdir -p "$LOGS"
export GH_CALLS="$T/gh-calls"; : > "$GH_CALLS"
mkdir -p "$T/bin"; export PATH="$T/bin:$PATH"
_pass=0; _fail=0

_report() { if [ "$1" = 0 ]; then _pass=$((_pass + 1)); else _fail=$((_fail + 1)); echo "  FAIL: $2${3:+ ($3)}"; fi; }
ok()    { local n="$1"; shift; "$@" >/dev/null 2>&1; _report $? "$n"; }
fails() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then _report 1 "$n" "expected failure"; else _report 0 "$n"; fi; }
eq()    { if [ "$2" = "$3" ]; then _report 0 "$1"; else _report 1 "$1" "want [$2], got [$3]"; fi; }
has()   { case "$3" in *"$2"*) _report 0 "$1" ;; *) _report 1 "$1" "[$2] not in [${3:0:300}]" ;; esac; }

stub_gh() {
  { printf '#!/usr/bin/env bash\necho "gh $*" >> "%s"\n' "$GH_CALLS"; printf '%s\n' "$1"; } > "$T/bin/gh"
  chmod +x "$T/bin/gh"
}

finish() {
  echo "$(basename "$0"): $_pass passed, $_fail failed"
  [ "$_fail" -eq 0 ]
}
