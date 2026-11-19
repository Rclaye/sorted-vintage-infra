#!/bin/bash
# The rebuild drill's steps (T077, SC-004), run by the Jenkins `rebuild-drill` stage on the lab
# host as bot, one step per call; each step can also be run by hand. Runbook:
# docs/runbooks/rebuild.md. Order proven on sv-spike (sprints/sprint-4/spikes.md): confirm the
# backups, destroy, merge the restore PR, apply.
#
#   rebuild-drill.sh mark <name>     record the time of a step in $DRILL_OUT/times.txt
#   rebuild-drill.sh preflight       read-only: restore files in initdb mode and naming the archive
#                                    each cluster writes to, a completed base backup per cluster,
#                                    archives current (make backups-check), then what must survive
#   rebuild-drill.sh restore-pr      the merged restore PR: every restore file in recovery mode,
#                                    from the archive in use to a new name
#   rebuild-drill.sh check-data      after the rebuild: each cluster archiving to its new name, and
#                                    the orders, listings and accounts from preflight are back
#   rebuild-drill.sh purchase        the scripted purchase and declined card (verify_purchase.py)
#   rebuild-drill.sh report          times.txt to rebuild-drill.json and rebuild-drill.txt
#
# Settings: DRILL_OUT (default ./drill), SV_GITOPS (a gitops checkout at main), SV_APP (an app
# checkout, for purchase), DRILL_VENV (venv for purchase, default $HOME/sv-spikes/rebuild-drill).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA="$(cd "$HERE/../.." && pwd)"
. "$HERE/common.sh"

DRILL_OUT="${DRILL_OUT:-$PWD/drill}"
SV_GITOPS="${SV_GITOPS:-}"
TIMES="$DRILL_OUT/times.txt"
BEFORE="$DRILL_OUT/before.txt"

# Each database cluster and its committed restore file in gitops (T076, T110).
CLUSTERS="sv-dev/pg:platform/postgres/overlays/dev/restore.yaml
sv-prod/pg:platform/postgres/overlays/prod/restore.yaml
keycloak/keycloak-db:platform/keycloak/db/restore.yaml"

mark() { mkdir -p "$DRILL_OUT"; echo "$1 $(date +%s)" >>"$TIMES"; log "mark $1"; }

need_gitops() {
  [ -n "$SV_GITOPS" ] && [ -d "$SV_GITOPS/platform/postgres" ] || die "set SV_GITOPS to a sorted-vintage-gitops checkout"
}

# "<mode> <from> <to>" for a restore file. initdb: from and to are both the archive written to.
# recovery: from is the externalClusters source, to the archive written to from now on.
restore_mode() {
  awk '
    /^[[:space:]]*#/ { next }
    /^spec:/ { spec = 1; next }
    spec && /^  [A-Za-z]/ { sect = $1; sub(/:$/, "", sect) }
    spec && /^[[:space:]]+recovery:/ { rec = 1 }
    /serverName:/ {
      match($0, /serverName: *[A-Za-z0-9._-]+/); v = substr($0, RSTART, RLENGTH); sub(/serverName: */, "", v)
      if (sect == "externalClusters") from = v; else if (sect == "plugins") to = v
    }
    END { if (rec) print "recovery", from, to; else print "initdb", to, to }
  ' "$1"
}

# The archive a live cluster writes to.
live_archive() {
  k -n "$1" get cluster "$2" -o jsonpath='{.spec.plugins[?(@.isWALArchiver==true)].parameters.serverName}'
}

# psql as postgres on a cluster's primary: psql <ns> <cluster> <db> <query>
psql_on() {
  pod=$(k -n "$1" get cluster "$2" -o jsonpath='{.status.currentPrimary}')
  [ -n "$pod" ] || die "$1/$2 has no current primary"
  k -n "$1" exec -i "$pod" -c postgres -- psql -U postgres -d "$3" -At -F ' ' -c "$4" </dev/null
}

# What must survive, one "key value..." per line.
snapshot() {
  echo "dev_orders $(psql_on sv-dev pg orders 'select count(*) from orders')"
  echo "dev_newest_order $(psql_on sv-dev pg orders 'select id from orders order by created_at desc limit 1')"
  echo "dev_listings $(psql_on sv-dev pg listings 'select count(*) from listing')"
  echo "prod_listings $(psql_on sv-prod pg listings 'select count(*) from listing')"
  psql_on keycloak keycloak-db keycloak \
    "select 'users_' || replace(r.name, '-', '_'), count(*) from user_entity u join realm r on r.id = u.realm_id group by r.name order by r.name"
}

preflight() {
  require_lab_user; require_docker; need_gitops
  rm -rf "$DRILL_OUT"; mkdir -p "$DRILL_OUT"
  k get --raw /readyz >/dev/null 2>&1 || die "the lab is not up (make up); nothing to drill"
  : >"$DRILL_OUT/archives.txt"
  for entry in $CLUSTERS; do
    c=${entry%%:*}; ns=${c%%/*}; name=${c#*/}; file="$SV_GITOPS/${entry#*:}"
    read -r mode from _ <<<"$(restore_mode "$file")"
    [ "$mode" = initdb ] || die "$file on gitops main is already in recovery mode: merge it only after the destroy (runbook step 3)"
    live=$(live_archive "$ns" "$name")
    [ "$live" = "$from" ] || die "$c writes to archive '$live' but $file names '$from'"
    newest=$(k -n "$ns" get backups.postgresql.cnpg.io -o json | jq -r --arg n "$name" \
      '[.items[] | select(.spec.cluster.name == $n and .status.phase == "completed")] | sort_by(.status.stoppedAt) | last | .status.stoppedAt // empty')
    [ -n "$newest" ] || die "$c has no completed base backup under '$live': take one and wait (runbook step 1)"
    log "$c: initdb mode, archiving to $live, newest completed base backup $newest"
    echo "$c $live" >>"$DRILL_OUT/archives.txt"
  done
  log "checking the archives are current (make backups-check, about 2 minutes)"
  DRY_RUN=1 "$HERE/down.sh"
  snapshot >"$BEFORE"
  log "must survive the rebuild:"; sed 's/^/  /' "$BEFORE"
}

restore_pr() {
  need_gitops
  [ -f "$DRILL_OUT/archives.txt" ] || die "no $DRILL_OUT/archives.txt: run preflight first"
  bad=""
  for entry in $CLUSTERS; do
    c=${entry%%:*}; file="$SV_GITOPS/${entry#*:}"
    was=$(awk -v c="$c" '$1 == c { print $2 }' "$DRILL_OUT/archives.txt")
    read -r mode from to <<<"$(restore_mode "$file")"
    if [ "$mode" != recovery ]; then bad="$bad
  ${entry#*:} is still in initdb mode"
    elif [ "$from" != "$was" ]; then bad="$bad
  ${entry#*:} recovers from '$from', but the data is in '$was'"
    elif [ -z "$to" ] || [ "$to" = "$from" ]; then bad="$bad
  ${entry#*:} must archive to a new name, not '${to:-nothing}'"
    else
      log "$c: recover from $from, archive to $to"
    fi
  done
  [ -z "$bad" ] || die "the restore PR on gitops main is not right:$bad"
}

check_data() {
  need_gitops; require_lab_user
  [ -f "$BEFORE" ] || die "no $BEFORE: run preflight first"
  for entry in $CLUSTERS; do
    c=${entry%%:*}; ns=${c%%/*}; name=${c#*/}
    read -r _ _ to <<<"$(restore_mode "$SV_GITOPS/${entry#*:}")"
    live=$(live_archive "$ns" "$name")
    [ "$live" = "$to" ] || die "$c archives to '$live', not the new name '$to'"
    cond=$(k -n "$ns" get cluster "$name" -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}')
    [ "$cond" = True ] || die "$c: ContinuousArchiving is '${cond:-missing}' (restore not done, see the runbook)"
    log "$c recovered and archiving to $to"
  done
  after=$(snapshot)
  printf '%s\n' "$after" >"$DRILL_OUT/after.txt"
  newest=$(awk '$1 == "dev_newest_order" { print $2 }' "$BEFORE")
  if [ -n "$newest" ]; then
    found=$(psql_on sv-dev pg orders "select count(*) from orders where id = '$newest'")
    [ "$found" = 1 ] || die "the newest order before the drill ($newest) is not in sv-dev"
  fi
  while read -r key value; do
    [ "$key" = dev_newest_order ] && continue
    now=$(printf '%s\n' "$after" | awk -v k="$key" '$1 == k { print $2 }')
    [ "${now:-0}" -ge "$value" ] || die "$key was $value before the drill and is ${now:-missing} now"
    log "$key: $value before, $now now"
  done <"$BEFORE"
}

purchase() {
  require_lab_user
  [ -n "${SV_APP:-}" ] && [ -d "$SV_APP/services/seed" ] || die "set SV_APP to a sorted-vintage-app checkout"
  venv="${DRILL_VENV:-$HOME/sv-spikes/rebuild-drill}"
  if [ ! -x "$venv/bin/python" ]; then
    uv venv -q --python 3.12.16 "$venv"
    uv pip install -q --python "$venv/bin/python" -r "$SV_APP/services/seed/requirements-dev.txt"
  fi
  PYTHONPATH="$SV_APP/services/seed" "$venv/bin/python" "$INFRA/sprints/sprint-3/verify_purchase.py"
}

# Durations between marks. SC-004 is from the start of the apply (an empty lab host) to a working
# purchase; the destroy and the wait for the restore PR are reported apart.
report() {
  [ -f "$TIMES" ] || die "no $TIMES"
  t() { awk -v k="$1" '$1 == k { v = $2 } END { print v }' "$TIMES"; }
  d() { a=$(t "$1"); b=$(t "$2"); [ -n "$a" ] && [ -n "$b" ] && echo $(( b - a )) || echo null; }
  sc004=$(d apply_start purchase_done)
  jq -n --arg build "${BUILD_TAG:-by hand}" --arg commit "${GIT_COMMIT:-$(git -C "$INFRA" rev-parse HEAD 2>/dev/null || echo unknown)}" \
    --argjson destroy "$(d destroy_start destroy_done)" --argjson pr_wait "$(d destroy_done apply_start)" \
    --argjson apply "$(d apply_start apply_done)" --argjson healthy "$(d apply_done healthy)" \
    --argjson restore_check "$(d healthy data_checked)" --argjson purchase "$(d data_checked purchase_done)" \
    --argjson sc004 "$sc004" --rawfile marks "$TIMES" \
    '{build: $build, infra_commit: $commit, seconds: {destroy: $destroy, waiting_for_restore_pr: $pr_wait,
      apply: $apply, apply_to_healthy: $healthy, restore_check: $restore_check, purchase: $purchase,
      sc004_empty_host_to_purchase: $sc004}, sc004_target_seconds: 1800,
      sc004_pass: ($sc004 != null and $sc004 < 1800),
      marks: ($marks | split("\n") | map(select(length > 0) | split(" ") | {(.[0]): (.[1] | tonumber)}) | add)}' \
    >"$DRILL_OUT/rebuild-drill.json"
  {
    echo "Rebuild drill, ${BUILD_TAG:-by hand}"
    jq -r '.seconds | to_entries[] | "  \(.key): \(if .value == null then "not reached" else "\(.value / 60 | floor) min \(.value % 60) s" end)"' "$DRILL_OUT/rebuild-drill.json"
    jq -r '"SC-004 (under 30 min): \(if .sc004_pass then "PASS" else "not met" end)"' "$DRILL_OUT/rebuild-drill.json"
    [ -f "$BEFORE" ] && { echo "Before:"; sed 's/^/  /' "$BEFORE"; }
    [ -f "$DRILL_OUT/after.txt" ] && { echo "After:"; sed 's/^/  /' "$DRILL_OUT/after.txt"; }
  } >"$DRILL_OUT/rebuild-drill.txt"
  cat "$DRILL_OUT/rebuild-drill.txt"
}

case "${1:-}" in
  mark) mark "${2:?mark needs a name}" ;;
  preflight) preflight ;;
  restore-pr) restore_pr ;;
  check-data) check_data ;;
  purchase) purchase ;;
  report) report ;;
  *) sed -n '5,17p' "$0"; exit 2 ;;
esac
