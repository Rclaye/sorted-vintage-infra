#!/bin/bash
# make down (T013, FR-023, research R14): end a lab session. Read-only: it creates and changes
# nothing in the cluster. For every CloudNativePG Cluster it reads the ContinuousArchiving
# condition and the instance's own metrics (port 9187, through the API server):
#   - archiving healthy: condition True, no failure newer than the last success
#   - nothing waiting:   cnpg_collector_pg_wal_archive_status{value="ready"} == 0
# then waits one archive_timeout (60s), so a recent write is switched out and archived, checks
# again, and only then stops the Kind node. The recovery point is about one minute of writes.
# Not "last archive younger than 120s": an idle database archives nothing, so that rule would
# never let the session end.
# DRY_RUN=1 runs every check but leaves the node running (make backups-check).
set -euo pipefail
. "$(dirname "$0")/common.sh"

ARCHIVE_TIMEOUT="${ARCHIVE_TIMEOUT:-60}"
WAIT_MAX="${WAIT_MAX:-300}"

require_lab_user
require_docker
node_running || { log "node $NODE is not running; nothing to do"; exit 0; }
k get --raw /readyz >/dev/null 2>&1 || die "the Kubernetes API does not answer; not stopping blind"

clusters=$(k get clusters.postgresql.cnpg.io -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')
[ -n "$clusters" ] || log "no CloudNativePG clusters found"

metric() { printf '%s\n' "$2" | awk -v m="$1" '$1==m {print $2; exit}'; }

# Prints nothing when the cluster is safe to stop, else the reason.
check_cluster() {
  ns=${1%%/*}; name=${1#*/}
  cond=$(k -n "$ns" get cluster "$name" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}')
  [ "$cond" = "True" ] || { echo "ContinuousArchiving is '${cond:-missing}'"; return; }
  pod=$(k -n "$ns" get cluster "$name" -o jsonpath='{.status.currentPrimary}')
  [ -n "$pod" ] || { echo "no current primary"; return; }
  m=$(k get --raw "/api/v1/namespaces/$ns/pods/$pod:9187/proxy/metrics" 2>/dev/null | grep -E '^cnpg_(collector_up|collector_pg_wal_archive_status|pg_stat_archiver_last_(archived|failed)_time)[{ ]') \
    || { echo "cannot read metrics from $pod"; return; }
  up=$(printf '%s\n' "$m" | awk '/^cnpg_collector_up/ {print $2; exit}')
  ready=$(metric 'cnpg_collector_pg_wal_archive_status{value="ready"}' "$m")
  ok_t=$(metric cnpg_pg_stat_archiver_last_archived_time "$m")
  fail_t=$(metric cnpg_pg_stat_archiver_last_failed_time "$m")
  [ "$up" = "1" ] || { echo "metrics collector is not up"; return; }
  [ -n "$ready" ] || { echo "no archive_status metric"; return; }
  if awk -v f="${fail_t:--1}" -v o="${ok_t:--1}" 'BEGIN{exit !(f > o)}'; then
    echo "last archive attempt FAILED (failure newer than last success)"; return
  fi
  ready=${ready%.*}
  [ "$ready" -eq 0 ] || { echo "$ready WAL file(s) waiting to be archived"; return; }
}

# Wait until every cluster is safe, re-checking every 10s for up to WAIT_MAX seconds.
check_all() {
  start=$(date +%s)
  while :; do
    pending=""
    for c in $clusters; do
      r=$(check_cluster "$c")
      [ -z "$r" ] || pending="$pending
  $c: $r"
    done
    [ -n "$pending" ] || return 0
    if [ $(( $(date +%s) - start )) -ge "$WAIT_MAX" ]; then
      die "archives are not current after ${WAIT_MAX}s; NOT stopping the node:$pending"
    fi
    log "waiting:$pending"
    sleep 10
  done
}

log "checking WAL archiving for: $(echo $clusters)"
check_all
log "archives current; waiting ${ARCHIVE_TIMEOUT}s (archive_timeout) for any recent write"
sleep "$ARCHIVE_TIMEOUT"
check_all
if [ "${DRY_RUN:-0}" = "1" ]; then
  log "archives still current; DRY_RUN=1, so node $NODE keeps running"
  exit 0
fi
log "archives still current; stopping node $NODE"
docker stop "$NODE" >/dev/null
log "lab is down"
