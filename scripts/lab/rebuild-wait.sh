#!/bin/bash
# After make rebuild: wait for the API and for every Argo CD Application to be Synced/Healthy.
# A fresh cluster pulls every image, so it gets 20 minutes instead of make up's 10.
set -euo pipefail
. "$(dirname "$0")/common.sh"
start=$(date +%s)
until k get --raw /readyz >/dev/null 2>&1; do
  [ $(( $(date +%s) - start )) -lt 300 ] || die "the API did not answer within 300s"
  sleep 5
done
wait_apps_healthy "${REBUILD_WAIT:-1200}"
