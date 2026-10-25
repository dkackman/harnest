#!/bin/bash -p
# The consumer's allowlisted spelling of perf-check.py: `./scripts/perf-check.sh <args>`.
# Isolated mode (-I) stays here, and neither PATH nor BASH_ENV/ENV from the caller can steer it.
PATH=/usr/bin:/bin
set -euo pipefail
unset BASH_ENV ENV
here="$(cd "${0%/*}" && pwd -P)"
exec /usr/bin/env -i PATH=/usr/bin:/bin "$(PATH=/usr/bin:/bin command -v python3 || echo /usr/bin/python3)" -I "$here/perf-check.py" "$@"
