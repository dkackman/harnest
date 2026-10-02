#!/usr/bin/env bash
# Make what a loop on this machine needs to run against another target's test
# bed (harnest#15; DW_TARGET, default mini-ai): the implementer's own clone,
# with its venv (the dw repo's install.sh). The test bed itself is set up on
# its host (README, "Another server"); scripts/testbed.sh runs it.
# Idempotent: anything already there is left as it is.
#
#   scripts/setup-mac-loop.sh --dry-run    # say what it would do
#   scripts/setup-mac-loop.sh
#
# It never stops or starts a server.
#
# Knobs:
#   DW_ORIGIN_URL       what to clone (default the dw repo on GitHub)
#   DW_TARGET           the test bed this loop targets (default mini-ai)
#   SOURCE_DIR          the implementer's clone (default ~/src/dkackman/dw-agent-<target>)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="${LOGS:-$REPO/logs}"
DW_TARGET="${DW_TARGET:-mini-ai}"
# shellcheck disable=SC1091
. "$REPO/providers.sh"
DW_ORIGIN_URL="${DW_ORIGIN_URL:-https://github.com/dkackman/diffusers-workflow.git}"
resolve_target || exit 1
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent-$DW_TARGET}"

dry=0
case "${1:-}" in
  --dry-run|-n) dry=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# clone <dir> <what it is>: a develop clone with its venv, unless there
clone() {
  local dir="$1" what="$2"
  if [ -d "$dir/.git" ]; then
    echo "$what: already there ($dir)"
  elif [ "$dry" = 1 ]; then
    echo "$what: would clone $DW_ORIGIN_URL (develop) into $dir and run install.sh"
    return 0
  else
    echo "$what: cloning into $dir"
    mkdir -p "$(dirname "$dir")"
    git clone -q -b develop "$DW_ORIGIN_URL" "$dir"
  fi
  if [ -f "$dir/venv/bin/activate" ]; then
    echo "$what: venv already there"
  elif [ "$dry" = 1 ]; then
    echo "$what: would run install.sh"
  else
    echo "$what: running install.sh"
    (cd "$dir" && bash ./install.sh)
  fi
}

clone "$SOURCE_DIR" "implementer clone"
cat <<EOM

Next:
  1. The test bed: scripts/testbed.sh $DW_TARGET status   (start / update if it isn't serving)
  2. One cycle against it:
     DW_TARGET=$DW_TARGET SHARED_PASSES=1 MAX_CYCLES=1 ./run-loop.sh
EOM
