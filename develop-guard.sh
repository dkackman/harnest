#!/bin/bash
# One-off guard for the 2026-09-21 loop run (pid 28654, logs/loop-run-2001.out):
# whenever a tester session starts, make sure lem is running origin/develop, and
# redeploy develop if it isn't. Writes to logs/develop-guard.log. Exits when the
# loop exits. Start it detached:  (nohup ./develop-guard.sh >/dev/null 2>&1 &)
cd "$(dirname "$0")" || exit 1
LOG=logs/develop-guard.log; RUN=logs/loop-run-2001.out; PID=28654
log(){ echo "[$(date '+%H:%M:%S')] $*" >>"$LOG"; }
seen=$(grep -c -E '^=== .*cycle [0-9]+: tester:' "$RUN")
log "guard started, tester sessions seen so far: $seen"
while kill -0 "$PID" 2>/dev/null; do
  cur=$(grep -c -E '^=== .*cycle [0-9]+: tester:' "$RUN")
  if [ "$cur" -gt "$seen" ]; then
    seen=$cur
    want=$(git -C ~/src/dkackman/diffusers-workflow ls-remote -q origin refs/heads/develop | cut -c1-7)
    have=$(ssh -o ConnectTimeout=8 -o BatchMode=yes lem 'cd ~/diffusers-workflow && echo "$(git branch --show-current) $(git rev-parse --short HEAD)"' 2>/dev/null)
    log "tester session starting; lem=$have origin/develop=$want"
    if [ "$have" != "develop $want" ]; then
      log "redeploying develop"
      ssh lem '~/diffusers-workflow/scripts/deploy.sh develop' >>"$LOG" 2>&1 || log "deploy failed rc=$?"
    fi
  fi
  sleep 20
done
log "loop pid exited; guard done"
