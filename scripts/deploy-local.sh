#!/usr/bin/env bash
# Deploy develop to the dw server on this machine and record what was
# deployed (harnest#15). deploy_cmd in providers.sh builds the call, with
# DW_DIR (the serving clone), DW_WORKSPACE, DW_HOST and DW_PORT; the Mac
# loop's implementer and the driver's develop check both run it.
#
# The record (DEPLOY_RECORD, default logs/.deployed.local) is what deployed_head reports for the
# local target. The serving clone's checkout can't stand in for it: dw's
# deploy.sh fast-forwards first and can still fail after (a job running
# past its wait, a server that won't start), and then the checkout names a
# commit that isn't serving. A failed deploy leaves the record as it was, so
# the next develop check sees the mismatch and deploys again.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${DW_DIR:?deploy-local.sh: DW_DIR (the serving clone) must be set}"
"$DW_DIR/scripts/deploy.sh" develop
record="${DEPLOY_RECORD:-$REPO/logs/.deployed.local}"
mkdir -p "$(dirname "$record")"
echo "$(git -C "$DW_DIR" branch --show-current) @ $(git -C "$DW_DIR" rev-parse --short HEAD)" > "$record"
