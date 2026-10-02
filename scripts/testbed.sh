#!/usr/bin/env bash
# Run a target's dw server from here: any box in target_row (providers.sh),
# over ssh, with dw's own scripts/deploy.sh doing every start (harnest#15).
#
#   scripts/testbed.sh <target> status            health, and the commit it serves
#   scripts/testbed.sh <target> update [branch]   deploy.sh: fetch, fast-forward, reinstall
#                                                 if pyproject moved, restart, wait for health
#                                                 (default develop, what the loop deploys)
#   scripts/testbed.sh <target> start             the checkout as it is (deploy.sh, no branch change)
#   scripts/testbed.sh <target> restart           the same as start: deploy.sh stops a running one
#   scripts/testbed.sh <target> stop              SIGTERM to what listens on the port, as deploy.sh does
#   scripts/testbed.sh <target> logs [n]          the last n lines of ~/dw-serve.log (default 100)
#
# deploy.sh refuses to restart under a running job (it says so); pass
# --force after the verb to override, as you would to deploy.sh itself.
# A loop or a regression run against the target holds its driver lock, and
# restarting the server under one fails its cases: stop, start and update
# refuse while that lock is held unless --force is given.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="${LOGS:-$REPO/logs}"
[ $# -ge 2 ] || { sed -n '2,19p' "$0" >&2; exit 2; }
DW_TARGET="$1"; verb="$2"; shift 2
force=""; args=()
for a in "$@"; do if [ "$a" = --force ]; then force=--force; else args+=("$a"); fi; done
# shellcheck disable=SC1091
. "$REPO/providers.sh"
resolve_target || exit 2
DW_TOKEN="${DW_TOKEN:-xyz}"
rsh() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$TARGET_HOST" "$@"; }

held() {  # a driver holds this target's lock, and --force wasn't given
  local owner="$LOGS/.driver.lock$TARGET_SUFFIX/owner" pid name
  [ -z "$force" ] && [ -f "$owner" ] && read -r pid name < "$owner" && kill -0 "$pid" 2>/dev/null \
    && { echo "$name (pid $pid) holds $DW_TARGET's driver lock: a restart now fails its cases. Stop it, or pass --force." >&2; return 0; }
  return 1
}

case "$verb" in
  status)
    echo "$DW_TARGET ($TARGET_HOST): $(deployed_head)"
    if h="$(target_health)"; then echo "serving: $h at $DW_URL"; else echo "not answering at $DW_URL"; exit 1; fi ;;
  update)
    held && exit 1
    rsh "$TARGET_DIR/scripts/deploy.sh ${args[0]:-develop} $force" ;;
  start|restart)
    held && exit 1
    rsh "$TARGET_DIR/scripts/deploy.sh $force" ;;
  stop)
    held && exit 1
    # What listens on the port, the way deploy.sh finds it, and SIGTERM only.
    # shellcheck disable=SC2016  # expanded on the target
    rsh 'pids="$(lsof -ti tcp:${DW_PORT:-8765} -sTCP:LISTEN 2>/dev/null || true)"
         [ -n "$pids" ] || { echo "not running"; exit 0; }
         kill -TERM $pids; for _ in $(seq 30); do kill -0 $pids 2>/dev/null || { echo "stopped"; exit 0; }; sleep 1; done
         echo "still running after 30 s (pids $pids): not escalating; look at ~/dw-serve.log" >&2; exit 1' ;;
  logs)
    rsh "tail -n ${args[0]:-100} ~/dw-serve.log" ;;
  *)
    echo "unknown verb '$verb' (status, update, start, restart, stop, logs)" >&2; exit 2 ;;
esac
