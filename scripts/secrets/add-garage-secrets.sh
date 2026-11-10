#!/usr/bin/env bash
# Adds Garage's secrets to ~/sv-terraform/secrets.auto.tfvars on the lab host, as bot (research R19).
# Per environment it generates the RPC secret, the admin token and two S3 keys (photos, backups) in the
# formats Garage expects. Asks for nothing, prints no values, and does nothing if a garage block exists.
# From the workstation (quoted, so ~ is bot's home on the lab host, not yours on the workstation):
#   ssh lab '~/Sorted-Vintage/src/sorted-vintage-infra/scripts/secrets/add-garage-secrets.sh'
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${SV_TF_DIR:-$HOME/sv-terraform}/secrets.auto.tfvars"
mkdir -p "$(dirname "$OUT")" && chmod 700 "$(dirname "$OUT")"

[[ "$(id -un)" == "${SV_LAB_USER:-bot}" ]] || { echo "Run this as ${SV_LAB_USER:-bot} on the lab host, not as $(id -un)."; exit 1; }
[[ -f "$OUT" ]] || { echo "$OUT does not exist; run scripts/secrets/new-secrets-tfvars.sh first."; exit 1; }
if grep -q '^garage = {' "$OUT"; then
  echo "$OUT already has a garage block; leaving it unchanged."
  exit 0
fi

hex() { openssl rand -hex "$1"; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cp "$OUT" "$TMP"
{
  echo
  echo "garage = {"
  for env in dev prod; do
    echo "  $env = {"
    echo "    rpc_secret         = \"$(hex 32)\""
    echo "    admin_token        = \"$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-48)\""
    echo "    photos_key_id      = \"GK$(hex 12)\""
    echo "    photos_secret_key  = \"$(hex 32)\""
    echo "    backups_key_id     = \"GK$(hex 12)\""
    echo "    backups_secret_key = \"$(hex 32)\""
    echo "  }"
  done
  echo "}"
} >>"$TMP"

install -m 600 "$TMP" "$OUT"
echo "Added Garage secrets for dev and prod to $OUT (mode 600). No values were shown."
