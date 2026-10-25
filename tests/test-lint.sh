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
# The Python stays ruff-clean (ruff.toml): `ruff check --fix . && ruff format .`
# fixes most of what these find. A missing ruff fails, rather than skips,
# so the check can't quietly stop happening.
if command -v ruff >/dev/null; then
  ok "ruff check (lint)" ruff check --quiet .
  ok "ruff format --check" ruff format --check --quiet .
else
  _report 1 "ruff is not on PATH: brew install ruff (or uv tool install ruff)"
fi
ok "classify.jq compiles" jq -f lib/classify.jq tests/fixtures/empty-board.json
# A suite's Fixtures section (`## Fixtures` to the next `## `) holds no `###`
# heading: harness/suite.py's fixtures_section stops at any heading up to
# `###`, so a sub-heading there would silently cut the section short.
for f in regression-suite-*.md; do
  fails "no ### heading in the Fixtures section of $f" \
    awk '/^```/ { fence = !fence } !fence && /^## / { inside = ($0 ~ /^## Fixtures/) ; next } inside && !fence && /^### / { found = 1 } END { exit !found }' "$f"
done
# The dashboard pages' scripts: the regression page rendered against a
# synthetic fleet state (every outcome and lane status). node is optional:
# the harness doesn't need it, so its absence skips rather than fails.
if command -v node >/dev/null; then
  ok "regression page renders" node tests/fixtures/render-regression.js dashboard/regression.html
fi
# Knobs: ${NAME:-...} reads in the drivers and scripts/*.sh, and
# environ.get("NAME"...) reads in lib/, scripts/ and harness/ Python, less
# the few that aren't settings.
internal="SESSION_HEADER TMPDIR PWD"
knobs() {
  grep -ohE '\$\{[A-Z][A-Z0-9_]+:-' run-*.sh providers.sh scripts/*.sh | sed 's/\${//; s/:-//'
  find lib scripts harness -name '*.py' -not -path '*/__pycache__/*' -print0 \
    | xargs -0 grep -ohE "environ\.get\( *[\"'][A-Z][A-Z0-9_]+[\"']" | sed -E "s/.*[\"']([A-Z0-9_]+)[\"']/\1/"
}
for k in $(knobs | sort -u); do
  case " $internal " in *" $k "*) continue ;; esac
  base="${k#CURATE_BUDGET_}"; [ "$base" = "$k" ] || [ "$base" = USD ] || k2="_$base"
  if grep -qw "$k" README.md || { [ -n "${k2:-}" ] && grep -q "\`${k2}\`" README.md; }; then _report 0 "knob $k"; else _report 1 "knob $k is not in README.md"; fi
  k2=""
done
finish
