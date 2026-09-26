#!/usr/bin/env bash
# Copy the regression suites' shared fixture media from lem's library to a
# server on this machine (harnest#15), so the cases that use them run there
# instead of being skipped.
#
#   scripts/sync-fixtures.sh --dry-run     # list what would come across; copies nothing
#   scripts/sync-fixtures.sh               # copy it
#
# The fixtures (asset:qa-cast/..., asset:uploads/qa-cast/..., asset:cast/...,
# asset:reference_sheet.jpg) were made on lem by hand, over many episodes,
# and several cases depend on exact properties of the files: a frame count,
# a level, a song that decodes above 0 dBFS. Regenerating them would not
# reproduce those, so they are copied byte for byte.
#
# lem is read, never written. The copy runs there at idle CPU and IO
# priority (nice, ionice) with a bandwidth cap, so it doesn't compete with
# a job lem is running. Still, it reads from lem: run it by hand when lem
# isn't busy. A file already present here is never overwritten.
#
# Knobs:
#   FIXTURE_SOURCE        rsync source (default lem:diffusers-workspace/common/assets)
#   DW_LOCAL_WORKSPACE    the local server's --workspace root; default: asked of the
#                         server at DW_URL (/api/server), which must be running
#   FIXTURE_BWLIMIT_KBPS  rsync --bwlimit (default 20000, about 20 MB/s)
set -euo pipefail

FIXTURE_SOURCE="${FIXTURE_SOURCE:-lem:diffusers-workspace/common/assets}"
FIXTURE_BWLIMIT_KBPS="${FIXTURE_BWLIMIT_KBPS:-20000}"
DW_URL="${DW_URL:-http://localhost:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"
root="${DW_LOCAL_WORKSPACE:-}"

dry=()
case "${1:-}" in
  --dry-run|-n) dry=(--dry-run) ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

if [ -z "$root" ]; then
  base="${DW_URL%/}"; base="${base%/mcp}"
  # The default workspace's root is the server's --workspace root, which
  # holds common/.
  root="$(curl -s -m 5 -H "Authorization: Bearer $DW_TOKEN" "$base/api/server?workspace=default" 2>/dev/null \
    | jq -er '.directories.workspace // empty' 2>/dev/null)" \
    || { echo "could not ask the server at $DW_URL for its workspace root: start it, or set DW_LOCAL_WORKSPACE" >&2; exit 1; }
fi
[ -d "$root" ] || { echo "not a directory on this machine: $root (the local server's --workspace root)" >&2; exit 1; }
dest="$root/common/assets"
mkdir -p "$dest"

echo "fixtures: $FIXTURE_SOURCE/ -> $dest/${dry:+ (dry run)}"
# Only the fixture trees, nothing else in lem's library. --ignore-existing:
# a file here is never replaced, so a rerun only fills gaps.
rsync -a --ignore-existing --prune-empty-dirs --itemize-changes ${dry[@]+"${dry[@]}"} \
  --bwlimit="$FIXTURE_BWLIMIT_KBPS" \
  -e "ssh -o BatchMode=yes -o ConnectTimeout=8" \
  --rsync-path="nice -n 19 ionice -c3 rsync" \
  --include='/qa-cast/***' \
  --include='/uploads/' --include='/uploads/qa-cast/***' \
  --include='/cast/***' \
  --include='/reference_sheet.jpg' \
  --exclude='*' \
  "$FIXTURE_SOURCE/" "$dest/"
