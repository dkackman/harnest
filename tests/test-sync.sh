#!/usr/bin/env bash
# scripts/sync-fixtures.sh offline: fake curl (the test bed's /api/server),
# a fake rsync that records each call's arguments, and a fake ssh. lem and
# mini-ai are never reached. Two hops: lem -> a stage here -> the test bed.
. "$(dirname "$0")/lib.sh"
sync="$HARNEST/scripts/sync-fixtures.sh"
root="/Users/don/diffusers-workspace"   # a path on the test bed, not here
printf '#!/usr/bin/env bash\necho "curl $*" >> "%s"\necho '"'"'{"directories":{"workspace":"%s"}}'"'"'\n' "$T/curl-calls" "$root" > "$T/bin/curl"
printf '#!/usr/bin/env bash\n{ printf "%%s\\n" "$@"; echo ----; } >> "%s"\n' "$T/rsync-args" > "$T/bin/rsync"
printf '#!/usr/bin/env bash\necho "ssh $*" >> "%s"\n' "$T/ssh-calls" > "$T/bin/ssh"
chmod +x "$T/bin/curl" "$T/bin/rsync" "$T/bin/ssh"
hop() { awk -v n="$1" '/^----$/ { i++; next } i == n - 1' "$T/rsync-args"; }   # hop <1|2>: that rsync call's arguments

out="$("$sync" --dry-run 2>&1)"
eq  "sync: dry run exits cleanly" 0 $?
has "sync: asks the test bed's server for its root" "http://mini-ai:8765/api/server?workspace=default" "$(cat "$T/curl-calls")"
eq  "sync: two rsyncs" 2 "$(grep -c '^----$' "$T/rsync-args")"
has "sync: first from lem's library" "lem:diffusers-workspace/common/assets/" "$(hop 1)"
has "  into the stage here" "$LOGS/.fixtures-stage/" "$(hop 1)"
has "  at idle priority on lem" "--rsync-path=nice -n 19 ionice -c3 rsync" "$(hop 1)"
has "  capped bandwidth" "--bwlimit=20000" "$(hop 1)"
has "  only the fixture trees" "--exclude=*" "$(hop 1)"
has "  qa-cast included" "--include=/qa-cast/***" "$(hop 1)"
has "then from the stage" "$LOGS/.fixtures-stage/" "$(hop 2)"
has "  into the test bed's shared library" "mini-ai:$root/common/assets/" "$(hop 2)"
has "  never overwriting a file there" "--ignore-existing" "$(hop 2)"
has "sync: dry run passes --dry-run to both" "--dry-run--dry-run" "$(hop 1 | grep -- --dry-run)$(hop 2 | grep -- --dry-run)"
has "sync: makes the library directory there" "mini-ai mkdir -p '$root/common/assets'" "$(cat "$T/ssh-calls")"
has "sync: says what it does" "(dry run)" "$out"

: > "$T/rsync-args"
"$sync" >/dev/null 2>&1
eq  "sync: a real run exits cleanly" 0 $?
eq  "sync: and is not a dry run" "" "$(grep -- '--dry-run' "$T/rsync-args" || true)"

printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
: > "$T/rsync-args"
has "sync: no server and no root is refused" "could not ask the server" "$("$sync" 2>&1)"
eq  "sync: before any rsync" "" "$(cat "$T/rsync-args")"
has "sync: an explicit root needs no server" "mini-ai:/srv/ws/common/assets/" "$(DW_TARGET_WORKSPACE=/srv/ws "$sync" >/dev/null 2>&1; cat "$T/rsync-args")"
has "sync: lem is the source, never the destination" "names where they go" "$(DW_TARGET=lem "$sync" 2>&1)"
has "sync: a stray argument is refused" "usage:" "$("$sync" --force 2>&1)"
finish
