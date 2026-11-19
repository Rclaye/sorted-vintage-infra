#!/usr/bin/env bash
# Sprint 3 verification (T075, T058, T113). Runs verify_sprint2.sh first (which runs Sprint 1's
# and the 5-second browse check, T113), then User Story 2's checks.
# Two ways to run it, both with the lab up (make up on the lab host):
#   from the workstation (default): reads, plus the checks that change something in sv-dev
#     (a scripted purchase and a declined card by the verify buyer, a malformed order event, and
#     the T058 double-sell load test on 100 fresh items);
#   on the lab host as bot with MINI=local: the Jenkins verify stage. Reads only.
# Same variables as verify_sprint1.sh, plus SV_APP (the sorted-vintage-app clone, default
# $SV_ROOT/sorted-vintage-app; workstation mode only) and SKIP_LOADTEST=1 to leave T058 out.
# Prod is only ever read.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA="$(cd "$HERE/../.." && pwd)"
if [[ -f "$INFRA/scripts/lab/local.env" ]]; then set -a; . "$INFRA/scripts/lab/local.env"; set +a; fi
MINI="${MINI:-${SV_LAB_SSH:-lab}}"
export MINI
[[ "$MINI" == local ]] && LOCAL=1 || LOCAL=0
SV_ROOT="${SV_ROOT:-$(dirname "$INFRA")}"
APP="${SV_APP:-$SV_ROOT/sorted-vintage-app}"
CLUSTER=sorted-vintage
# Where the workstation checks run on the lab host: the seed service's browser code and a venv
# from its pinned requirements (no other install).
RUNDIR='$HOME/sv-spikes/verify-sprint3'

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; }
remote() {
  if (( LOCAL )); then bash -c "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; $1"
  else ssh -o BatchMode=yes -o ConnectTimeout=8 "$MINI" "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; $1"; fi
}
k() { remote "kubectl --context kind-$CLUSTER $1"; }
proxy() { k "get --raw '/api/v1/namespaces/$1/services/http:$2:80/proxy$3'"; }

bash "$INFRA/sprints/sprint-2/verify_sprint2.sh"
echo

echo "Orders and Notifications (Tickets 3.4, 3.6, 3.7)"
for svc in orders notifications; do
  proxy sv-dev "$svc" /healthz | grep -q '"status":"ok"' && pass "sv-dev $svc /healthz ok" \
    || fail "sv-dev $svc /healthz is not ok"
  # Prod runs them at 0 replicas until they are promoted (T074); a promoted one must be healthy.
  replicas="$(k "-n sv-prod get deploy $svc -o jsonpath={.spec.replicas}")"
  if [[ "${replicas:-x}" == 0 ]]; then
    pass "sv-prod $svc deployed at 0 replicas, not promoted yet"
  else
    proxy sv-prod "$svc" /healthz | grep -q '"status":"ok"' && pass "sv-prod $svc /healthz ok" \
      || fail "sv-prod $svc /healthz is not ok"
  fi
done

echo "RabbitMQ topology and users (T070, T074)"
for ns in sv-dev sv-prod; do
  objects="$(k "-n $ns get exchanges.rabbitmq.com,queues.rabbitmq.com,bindings.rabbitmq.com,users.rabbitmq.com,permissions.rabbitmq.com -o json")"
  counts="$(jq -r '[.items[] | .kind] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' <<<"$objects")"
  [[ "$counts" == "Binding=3 Exchange=2 Permission=2 Queue=2 User=2" ]] \
    || fail "$ns topology objects are $counts, not 3 bindings, 2 exchanges, 2 permissions, 2 queues, 2 users"
  notready="$(jq -r '[.items[] | select(([.status.conditions[]? | select(.type == "Ready") | .status] | first) != "True") | "\(.kind)/\(.metadata.name)"] | join(" ")' <<<"$objects")"
  [[ -z "$notready" ]] && pass "$ns: 2 exchanges, 2 queues, 3 bindings, 2 users and 2 permissions Ready" \
    || fail "$ns not Ready: $notready"
done
consumers="$(k "-n sv-dev exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl -q list_queues name consumers" \
  | awk '$1 == "notifications.orders" { print $2 }')"
[[ "${consumers:-0}" -ge 1 ]] && pass "sv-dev notifications.orders has $consumers consumer(s)" \
  || fail "nothing consumes sv-dev notifications.orders"

echo "Stripe payment events reach Payments (T049, T067)"
for ns in sv-dev sv-prod; do
  # The forwarder's platform session logs every delivery as "<--  [code] POST .../webhooks/stripe".
  log="$(k "-n $ns logs deploy/stripe-forwarder -c platform --tail=500")"
  good="$(grep -c '\[200\] POST http://payments/webhooks/stripe ' <<<"$log" || true)"
  bad="$(grep -E '\[[0-9]{3}\] POST http://payments/webhooks/stripe ' <<<"$log" | grep -vc '\[200\]' || true)"
  [[ "$bad" == 0 ]] && pass "$ns forwarder: $good payment events answered 200, none refused" \
    || fail "$ns forwarder: $bad payment events not answered 200"
done
if (( LOCAL )); then
  skip "unsigned payment webhooks (workstation only)"
else
  for ns in sv-dev sv-prod; do
    out="$(remote "printf '{}' | kubectl --context kind-$CLUSTER create --raw /api/v1/namespaces/$ns/services/http:payments:80/proxy/webhooks/stripe -f - 2>&1" || true)"
    if grep -q BadRequest <<<"$out"; then
      pass "$ns refuses an unsigned payment webhook with 400"
    elif [[ "$ns" == sv-prod ]] && grep -q NotFound <<<"$out"; then
      # Prod's Payments predates Ticket 3.5 until it is promoted; then this must answer 400.
      skip "sv-prod Payments has no /webhooks/stripe yet (Ticket 3.5 not promoted)"
    else
      fail "$ns accepted or mishandled an unsigned payment webhook: $out"
    fi
  done
fi

echo "Buying end to end as the verify buyer (T075)"
if (( LOCAL )); then
  skip "scripted purchase, declined card and dead letter (workstation only: they write to sv-dev)"
  skip "T058 double-sell load test (workstation only)"
else
  [[ -d "$APP/services/seed" && -f "$APP/tests/load/double_sell.py" ]] \
    || fail "no sorted-vintage-app clone with services/seed and tests/load at $APP (set SV_APP)"
  remote "mkdir -p $RUNDIR/services"
  rsync -a --delete --exclude .venv --exclude __pycache__ --exclude .pytest_cache --exclude .ruff_cache \
    "$APP/services/seed" "$MINI:${RUNDIR#\$HOME/}/services/"
  rsync -a "$APP/tests" "$APP/Makefile" "$HERE/verify_purchase.py" "$MINI:${RUNDIR#\$HOME/}/"
  remote "cd $RUNDIR && { [ -x .venv/bin/python ] || { uv venv -q --python 3.12.16 .venv && uv pip install -q --python .venv/bin/python -r services/seed/requirements-dev.txt; }; }" \
    || fail "could not prepare the venv on the lab host"
  remote "cd $RUNDIR && PYTHONPATH=services/seed .venv/bin/python verify_purchase.py" \
    || fail "purchase check failed (above)"

  echo "Double sales under load (T058, SC-003)"
  if [[ "${SKIP_LOADTEST:-0}" == 1 ]]; then
    skip "T058 (SKIP_LOADTEST=1)"
  else
    out="$(remote "cd $RUNDIR && make -s loadtest-double-sell ENV=dev PYTHON=.venv/bin/python" 2>&1)" \
      || { printf '%s\n' "$out"; fail "the double-sell test failed (above)"; }
    printf '%s\n' "$out" | grep -E '^  ' || true
    summary="$(grep '^{' <<<"$out")"
    double="$(jq -r .double_sold <<<"$summary")"; attempts="$(jq -r .attempts <<<"$summary")"
    items="$(jq -r .items <<<"$summary")"; paid="$(jq -r .paid_items <<<"$summary")"
    [[ "$double" == 0 ]] && pass "$attempts attempts across $items items: $paid sold, none twice (SC-003)" \
      || fail "$double items were sold twice"
  fi
fi

echo
echo "Sprint 3 verification passed."
echo "Manual checks (quickstart step 3 by hand, memory checkpoint 1) are recorded in sprint3_retro.md."
