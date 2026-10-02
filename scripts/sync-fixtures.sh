#!/usr/bin/env bash
# Copy the regression suites' shared fixture media from lem's library to
# another target's test bed (harnest#15; DW_TARGET, default mini-ai), so the
# cases that use them run there instead of being skipped.
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
# lem is read, never written. The read from lem runs there at idle CPU and IO
# priority (nice, ionice) with a bandwidth cap, so it doesn't compete with
# a job lem is running. Still, it reads from lem: run it by hand when lem
# isn't busy. A file already on the test bed is never overwritten.
#
# Knobs:
#   FIXTURE_SOURCE        rsync source (default lem:diffusers-workspace/common/assets)
#   DW_TARGET             where they go (default mini-ai; target_row in providers.sh)
#   DW_TARGET_WORKSPACE   that server's --workspace root, a path on its host; default:
#                         asked of the server (/api/server), which must be running
#   FIXTURE_STAGE         the copy kept here between the two hops (default logs/.fixtures-stage)
#   FIXTURE_BWLIMIT_KBPS  rsync --bwlimit (default 20000, about 20 MB/s)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="${LOGS:-$REPO/logs}"
DW_TARGET="${DW_TARGET:-mini-ai}"
# shellcheck disable=SC1091
. "$REPO/providers.sh"
resolve_target || exit 1
[ "$DW_TARGET" != lem ] || { echo "the fixtures come from lem; DW_TARGET names where they go" >&2; exit 2; }
FIXTURE_SOURCE="${FIXTURE_SOURCE:-lem:diffusers-workspace/common/assets}"
FIXTURE_BWLIMIT_KBPS="${FIXTURE_BWLIMIT_KBPS:-20000}"
FIXTURE_STAGE="${FIXTURE_STAGE:-$LOGS/.fixtures-stage}"
DW_TOKEN="${DW_TOKEN:-xyz}"
root="${DW_TARGET_WORKSPACE:-}"

dry=()
case "${1:-}" in
  --dry-run|-n) dry=(--dry-run) ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

if [ -z "$root" ]; then
  base="${DW_URL%/}"; base="${base%/mcp}"
  # The default workspace's root is the server's --workspace root, which
  # holds common/. A path on the test bed, not here.
  root="$(curl -s -m 5 -H "Authorization: Bearer $DW_TOKEN" "$base/api/server?workspace=default" 2>/dev/null \
    | jq -er '.directories.workspace // empty' 2>/dev/null)" \
    || { echo "could not ask the server at $DW_URL for its workspace root: scripts/testbed.sh $DW_TARGET start, or set DW_TARGET_WORKSPACE" >&2; exit 1; }
fi
dest="$TARGET_HOST:$root/common/assets"
ssh_opts=(-e "ssh -o BatchMode=yes -o ConnectTimeout=8")
mkdir -p "$FIXTURE_STAGE"

# rsync can't copy from one remote to another, so lem's fixtures are
# staged here first (kept, so a rerun reads only what changed on lem),
# then copied on. Only the fixture trees, nothing else in lem's library.
echo "fixtures: $FIXTURE_SOURCE/ -> $FIXTURE_STAGE/ -> $dest/${dry:+ (dry run)}"
rsync -a --prune-empty-dirs --itemize-changes ${dry[@]+"${dry[@]}"} \
  --bwlimit="$FIXTURE_BWLIMIT_KBPS" "${ssh_opts[@]}" \
  --rsync-path="nice -n 19 ionice -c3 rsync" \
  --include='/qa-cast/***' \
  --include='/uploads/' --include='/uploads/qa-cast/***' \
  --include='/cast/***' \
  --include='/reference_sheet.jpg' \
  --exclude='*' \
  "$FIXTURE_SOURCE/" "$FIXTURE_STAGE/"
# --ignore-existing: a file on the test bed is never replaced, so a rerun
# only fills gaps. (A dry run staged nothing, so it lists only what's staged.)
ssh -o BatchMode=yes -o ConnectTimeout=8 "$TARGET_HOST" "mkdir -p '$root/common/assets'"
rsync -a --ignore-existing --itemize-changes ${dry[@]+"${dry[@]}"} "${ssh_opts[@]}" "$FIXTURE_STAGE/" "$dest/"
