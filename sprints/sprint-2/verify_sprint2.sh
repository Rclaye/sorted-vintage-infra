#!/usr/bin/env bash
# Sprint 2 verification (T115, T113). Runs verify_sprint1.sh first, then Sprint 2's checks.
# Two ways to run it, both with the lab up (make up on the lab host):
#   from the workstation (default): reads, plus the checks that change something in sv-dev
#     (a scripted listing by the verify seller, published, timed in search, then deleted);
#   on the lab host as bot with MINI=local: the Jenkins verify stage. Reads only; the checks
#     that write are skipped (plan.md Complexity Tracking).
# Same variables as verify_sprint1.sh (SV_ROOT, SV_GITOPS, SV_OWNER, MINI, MINI_INFRA, SV_TF_DIR).
# Prod is only ever read.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA="$(cd "$HERE/../.." && pwd)"
if [[ -f "$INFRA/scripts/lab/local.env" ]]; then set -a; . "$INFRA/scripts/lab/local.env"; set +a; fi
MINI="${MINI:-${SV_LAB_SSH:-lab}}"
export MINI
[[ "$MINI" == local ]] && LOCAL=1 || LOCAL=0
CLUSTER=sorted-vintage
SEEDED=50          # listings the seed job publishes (T051)
SEARCH_WITHIN=5    # seconds from publish to search (T113, SC-002)

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; }
remote() {
  if (( LOCAL )); then bash -c "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; $1"
  else ssh -o BatchMode=yes -o ConnectTimeout=8 "$MINI" "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; $1"; fi
}
k() { remote "kubectl --context kind-$CLUSTER $1"; }
proxy() { k "get --raw '/api/v1/namespaces/$1/services/http:$2:80/proxy$3'"; }

bash "$INFRA/sprints/sprint-1/verify_sprint1.sh"
echo

echo "Services (Tickets 2.3 to 2.5)"
for ns in sv-dev sv-prod; do
  proxy "$ns" listings /healthz | grep -q '"status":"UP"' && pass "$ns listings /healthz UP" || fail "$ns listings /healthz is not UP"
  proxy "$ns" payments /healthz | grep -q '"status":"ok"' && pass "$ns payments /healthz ok" || fail "$ns payments /healthz is not ok"
  ready="$(k "-n $ns get deploy stripe-forwarder -o jsonpath={.status.readyReplicas}")"
  [[ "${ready:-0}" -ge 1 ]] && pass "$ns Stripe forwarder ready" || fail "$ns Stripe forwarder has no ready replica"
done

echo "BFF through its Ingress (Ticket 2.6, research R18)"
# On the lab host, through Traefik on 443 with the browser's names and port, TLS checked against
# the mkcert CA (never -k).
for env in dev prod; do
  code="$(remote "curl -s -o /dev/null -w '%{http_code}' --cacert \"\$(mkcert -CAROOT)/rootCA.pem\" \
    --connect-to $env.sortedvtg.lan:8443:127.0.0.1:443 https://$env.sortedvtg.lan:8443/healthz")"
  [[ "$code" == 200 ]] && pass "https://$env.sortedvtg.lan:8443/healthz 200 with the mkcert CA" \
    || fail "BFF $env through the Ingress answered $code"
done

echo "Seed job (T051)"
job="$(k "-n sv-dev get job seed -o jsonpath={.status.succeeded}" 2>/dev/null || true)"
[[ "$job" == 1 ]] && pass "seed job succeeded in sv-dev" || fail "seed job has not succeeded in sv-dev"
seeded="$(proxy sv-dev listings '/listings?limit=60' | jq '[.items[] | select(.title | test(" #[0-9]{2}$"))] | length')"
[[ "$seeded" -ge "$SEEDED" ]] && pass "$seeded seeded listings in search" || fail "only $seeded of $SEEDED seeded listings in search"
photos="$(proxy sv-dev listings '/listings?limit=60' | jq '[.items[] | select(.title | test(" #[0-9]{2}$")) | select((.photos | length) == 0)] | length')"
[[ "$photos" == 0 ]] && pass "every seeded listing has a photo" || fail "$photos seeded listings have no photo"

echo "Stripe webhooks (T045)"
if (( LOCAL )); then
  skip "bad signatures (workstation only)"
else
  # POST through the API server's service proxy, with no Stripe-Signature header: Payments must
  # refuse it with 400 before reading the body. The proxy reports a 400 as BadRequest.
  for ns in sv-dev sv-prod; do
    out="$(remote "printf '{}' | kubectl --context kind-$CLUSTER create --raw /api/v1/namespaces/$ns/services/http:payments:80/proxy/webhooks/stripe-connect -f - 2>&1" || true)"
    grep -q BadRequest <<<"$out" && pass "$ns refuses an unsigned Connect webhook with 400" || fail "$ns accepted or mishandled an unsigned webhook: $out"
  done
  skip "/webhooks/stripe (payment events) arrives in Sprint 3"
fi

echo "Selling end to end as the verify seller (T046 to T048, T113)"
if (( LOCAL )); then
  skip "scripted listing, photos, search timing and delete (workstation only: they write to sv-dev)"
else
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$MINI" "SEARCH_WITHIN=$SEARCH_WITHIN bash -s" < "$HERE/verify_selling.sh" \
    || fail "selling check failed (above)"
fi

echo
echo "Sprint 2 verification passed."
echo "Manual checks (memory with everything running, T119) are recorded in sprint2_retro.md."
