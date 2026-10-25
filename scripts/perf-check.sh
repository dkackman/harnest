#!/bin/bash
# The consumer's allowlisted spelling of perf-check.py: `./scripts/perf-check.sh <args>`.
# Isolated mode (-I) stays here, so the agent's cwd and sys.path cannot shadow anything.
set -euo pipefail
exec python3 -I "$(cd "$(dirname "$0")" && pwd)/perf-check.py" "$@"
