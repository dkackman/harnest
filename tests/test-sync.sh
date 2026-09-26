#!/usr/bin/env bash
# scripts/sync-fixtures.sh offline: fake curl (the local server's
# /api/server) and a fake rsync that records its arguments. lem is never
# reached.
. "$(dirname "$0")/lib.sh"
sync="$HARNEST/scripts/sync-fixtures.sh"
mkdir -p "$T/ws"
printf '#!/usr/bin/env bash\necho "curl $*" >> "%s"\necho '"'"'{"directories":{"workspace":"%s"}}'"'"'\n' "$T/curl-calls" "$T/ws" > "$T/bin/curl"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s"\n' "$T/rsync-args" > "$T/bin/rsync"
chmod +x "$T/bin/curl" "$T/bin/rsync"

out="$("$sync" --dry-run 2>&1)"
eq  "sync: dry run exits cleanly" 0 $?
has "sync: asks the local server for its root" "http://localhost:8765/api/server?workspace=default" "$(cat "$T/curl-calls")"
has "sync: into the shared library" "$T/ws/common/assets/" "$(cat "$T/rsync-args")"
has "sync: from lem's library" "lem:diffusers-workspace/common/assets/" "$(cat "$T/rsync-args")"
has "sync: dry run passes --dry-run" "--dry-run" "$(cat "$T/rsync-args")"
has "sync: never overwrites a file here" "--ignore-existing" "$(cat "$T/rsync-args")"
has "sync: idle priority on lem" "--rsync-path=nice -n 19 ionice -c3 rsync" "$(cat "$T/rsync-args")"
has "sync: capped bandwidth" "--bwlimit=20000" "$(cat "$T/rsync-args")"
has "sync: only the fixture trees" "--exclude=*" "$(cat "$T/rsync-args")"
has "sync: qa-cast included" "--include=/qa-cast/***" "$(cat "$T/rsync-args")"
has "sync: says what it does" "(dry run)" "$out"
ok  "sync: makes the library directory" test -d "$T/ws/common/assets"

"$sync" >/dev/null 2>&1
eq  "sync: a real run exits cleanly" 0 $?
eq  "sync: and is not a dry run" "" "$(grep -- '--dry-run' "$T/rsync-args" || true)"

printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
: > "$T/rsync-args"
has "sync: no server and no root is refused" "could not ask the server" "$("$sync" 2>&1)"
eq  "sync: before any rsync" "" "$(cat "$T/rsync-args")"
has "sync: an explicit root needs no server" "$T/ws/common/assets/" "$(DW_LOCAL_WORKSPACE="$T/ws" "$sync" >/dev/null 2>&1; cat "$T/rsync-args")"
has "sync: a root that isn't here is refused" "not a directory" "$(DW_LOCAL_WORKSPACE="$T/nope" "$sync" 2>&1)"
has "sync: a stray argument is refused" "usage:" "$("$sync" --force 2>&1)"
finish
