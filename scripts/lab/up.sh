#!/bin/bash
# make up (T013, FR-024): start a lab session. Refuses unless it runs as bot, Docker answers and
# Ollama is not running (the two do not fit in 16 GB together); then starts the Kind node and
# waits until every Argo CD Application is Synced and Healthy (10 minutes).
set -euo pipefail
. "$(dirname "$0")/common.sh"

require_lab_user
require_docker
if pgrep -i -x ollama >/dev/null 2>&1 || pgrep -i -f 'Ollama.app' >/dev/null 2>&1; then
  die "Ollama is running. Quit it in the admin account first (LocalMind and the lab do not fit together)."
fi
docker inspect "$NODE" >/dev/null 2>&1 || die "no Kind node '$NODE'. Build the lab with 'make rebuild'."

since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if node_running; then
  log "node $NODE is already running"
else
  log "starting node $NODE"
  docker start "$NODE" >/dev/null
  started=1
fi

log "waiting for the Kubernetes API"
start=$(date +%s)
until k get --raw /readyz >/dev/null 2>&1; do
  [ $(( $(date +%s) - start )) -lt 180 ] || die "the API did not answer within 180s"
  sleep 5
done

log "waiting for Argo CD apps to be reconciled and Synced/Healthy (up to 10 minutes)"
if [ "${started:-0}" = "1" ]; then wait_apps_healthy 600 "$since"; else wait_apps_healthy 600; fi
log "lab is up"
