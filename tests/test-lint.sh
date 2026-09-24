#!/usr/bin/env bash
# Static checks: every script parses under bash 3.2, shellcheck finds no
# errors, the Python parses, and every env knob a driver reads is named in
# the README (a knob nobody can find is a knob nobody sets on purpose).
. "$(dirname "$0")/lib.sh"
cd "$HARNEST" || exit 1
for f in providers.sh run-*.sh measure-base-ctx.sh tests/*.sh; do
  ok "bash -n $f" /bin/bash -n "$f"
done
if command -v shellcheck >/dev/null; then
  ok "shellcheck -S error" shellcheck -S error -s bash providers.sh run-*.sh tests/*.sh
fi
for f in agent-settings/hooks/guard.py tests/fake-gh.py contract/*.py bench/*.py; do
  ok "python parses $f" python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$f"
done
ok "classify.jq compiles" jq -f lib/classify.jq tests/fixtures/empty-board.json
# Knobs: ${NAME:-...} reads in the drivers, less the few that aren't settings.
internal="SESSION_HEADER TMPDIR"
for k in $(grep -ohE '\$\{[A-Z][A-Z0-9_]+:-' run-*.sh providers.sh | sed 's/\${//; s/:-//' | sort -u); do
  case " $internal " in *" $k "*) continue ;; esac
  base="${k#CURATE_BUDGET_}"; [ "$base" = "$k" ] || [ "$base" = USD ] || k2="_$base"
  if grep -qw "$k" README.md || { [ -n "${k2:-}" ] && grep -q "\`${k2}\`" README.md; }; then _report 0 "knob $k"; else _report 1 "knob $k is not in README.md"; fi
  k2=""
done
finish
