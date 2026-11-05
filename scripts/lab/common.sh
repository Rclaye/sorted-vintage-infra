# Shared settings and helpers for scripts/lab/*.sh (T013). Sourced, not run.
# macOS ships bash 3.2: no associative arrays, no ${var,,}.
CLUSTER_NAME="${CLUSTER_NAME:-sorted-vintage}"
NODE="${CLUSTER_NAME}-control-plane"
KCTX="${KCTX:-kind-${CLUSTER_NAME}}"
LAB_USER="${LAB_USER:-bot}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

k() { kubectl --context "$KCTX" "$@"; }
log() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_lab_user() {
  [ "$(id -un)" = "$LAB_USER" ] || die "run this as '$LAB_USER' on the mini (ADR-0008), not as '$(id -un)'"
}

require_docker() {
  docker info >/dev/null 2>&1 || die "Docker does not answer. Log in as $LAB_USER at the mini's screen so Docker Desktop runs, then retry."
}

node_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$NODE" 2>/dev/null)" = "true" ]
}

# Wait until every Argo CD Application is Synced and Healthy (timeout in seconds). With a second
# argument (UTC, 2026-11-05T01:43:58Z), an app also counts only once Argo CD has reconciled it
# after that time: right after a node restart the statuses are the saved ones from before the
# stop, and they read Synced/Healthy before anything has been checked.
wait_apps_healthy() {
  timeout="$1"; since="${2:-}"; start=$(date +%s)
  while :; do
    out=$(k -n argocd get applications.argoproj.io \
      -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status} {.status.reconciledAt}{"\n"}{end}' 2>/dev/null) || out=""
    total=$(printf '%s\n' "$out" | grep -c . || true)
    bad=$(printf '%s\n' "$out" | grep . | awk -v s="$since" '$2 != "Synced" || $3 != "Healthy" || (s != "" && $4 < s) {print $1, $2, $3, ($4 < s ? "not reconciled since start" : "")}' || true)
    if [ "$total" -gt 0 ] && [ -z "$bad" ]; then
      log "all $total Argo CD apps Synced/Healthy after $(( $(date +%s) - start ))s"
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      printf '%s\n' "$bad" >&2
      die "not every app is Synced/Healthy after ${timeout}s (listed above)"
    fi
    sleep 10
  done
}
