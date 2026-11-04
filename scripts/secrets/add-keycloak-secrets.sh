#!/usr/bin/env bash
# Adds Keycloak's secrets to terraform/bootstrap/secrets.auto.tfvars on the Mac mini, as bot (T025, R16).
# Generates the bootstrap admin password, the keycloak-db password, and one client secret per client and
# realm (bff, orders, payments, listings in sv-dev and sv-prod). Asks for nothing, prints no values, and
# does nothing if a keycloak block exists.
# From the Air (quoted, so ~ is bot's home on the mini, not yours on the Air):
#   ssh mac-mini-lab '~/Sorted-Vintage/src/sorted-vintage-infra/scripts/secrets/add-keycloak-secrets.sh'
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/terraform/bootstrap/secrets.auto.tfvars"

[[ "$(id -un)" == "${SV_LAB_USER:-bot}" ]] || { echo "Run this as ${SV_LAB_USER:-bot} on the mini, not as $(id -un)."; exit 1; }
[[ -f "$OUT" ]] || { echo "$OUT does not exist; run scripts/secrets/new-secrets-tfvars.sh first."; exit 1; }
if grep -q '^keycloak = {' "$OUT"; then
  echo "$OUT already has a keycloak block; leaving it unchanged."
  exit 0
fi

secret() { openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-40; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cp "$OUT" "$TMP"
{
  echo
  echo "keycloak = {"
  echo "  admin_password = \"$(secret)\""
  echo "  db_password    = \"$(secret)\""
  echo "  clients = {"
  for env in dev prod; do
    echo "    $env = {"
    for c in bff orders payments listings; do
      printf '      %-8s = "%s"\n' "$c" "$(secret)"
    done
    echo "    }"
  done
  echo "  }"
  echo "}"
} >>"$TMP"

install -m 600 "$TMP" "$OUT"
echo "Added Keycloak secrets to $OUT (mode 600). No values were shown."
