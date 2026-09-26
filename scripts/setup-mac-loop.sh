#!/usr/bin/env bash
# Make what the loop on this machine needs (harnest#15): the implementer's
# own clone, the serving clone the local server runs from, each with its
# venv (the dw repo's install.sh), and the server's workspace. Idempotent:
# anything already there is left as it is.
#
#   scripts/setup-mac-loop.sh --dry-run    # say what it would do
#   scripts/setup-mac-loop.sh
#
# It never stops or starts a server. After it, stop a server you started by
# hand, then deploy the serving clone (or just start the loop: its develop
# check deploys it).
#
# Knobs:
#   DW_ORIGIN_URL       what to clone (default the dw repo on GitHub)
#   SOURCE_DIR          the implementer's clone (default ~/src/dkackman/dw-agent-mps)
#   DW_LOCAL_DIR        the serving clone (providers.sh's default for DW_TARGET=local)
#   DW_LOCAL_WORKSPACE  the server's --workspace (providers.sh's default)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="${LOGS:-$REPO/logs}"
DW_TARGET=local
# shellcheck disable=SC1091
. "$REPO/providers.sh"
DW_ORIGIN_URL="${DW_ORIGIN_URL:-https://github.com/dkackman/diffusers-workflow.git}"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent-mps}"

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
clone "$DW_LOCAL_DIR" "serving clone"
if [ -d "$DW_LOCAL_WORKSPACE" ]; then
  echo "workspace: already there ($DW_LOCAL_WORKSPACE)"
elif [ "$dry" = 1 ]; then
  echo "workspace: would create $DW_LOCAL_WORKSPACE"
else
  mkdir -p "$DW_LOCAL_WORKSPACE"; echo "workspace: created $DW_LOCAL_WORKSPACE"
fi

cat <<EOM

Next:
  1. Stop a dw server you started by hand (what listens on the port:
     lsof -ti tcp:8765 -sTCP:LISTEN).
  2. Deploy the serving clone:
     DW_TARGET=local LOGS="$PWD/logs" bash -c '. ./providers.sh; resolve_target; deploy_target'
     or just start the loop: with nothing answering, it deploys the clone first:
     DW_TARGET=local SHARED_PASSES=1 MAX_CYCLES=1 ./run-loop.sh
EOM
