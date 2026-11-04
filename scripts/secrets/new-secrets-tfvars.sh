#!/usr/bin/env bash
# Writes terraform/bootstrap/secrets.auto.tfvars (git-ignored, mode 600) on the Mac mini, as bot.
# Asks for each environment's Stripe test keys without echoing them, and generates everything else:
#   - the webhook signing secret of each sandbox (stripe listen --print-secret, projects sv-dev and sv-prod)
#   - one database password per environment and database
#   - an mkcert certificate for *.sortedvtg.lan (the mkcert CA stays in bot's CAROOT; it is not installed here)
#   - Garage's RPC secret, admin token and S3 keys, through add-garage-secrets.sh
#   - Keycloak's admin and database passwords and client secrets, through add-keycloak-secrets.sh
# Nothing secret is printed. It refuses to overwrite an existing file.
# From the Air (quoted, so ~ is bot's home on the mini, not yours on the Air):
#   ssh -t mac-mini-lab '~/Sorted-Vintage/src/sorted-vintage-infra/scripts/secrets/new-secrets-tfvars.sh'
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/terraform/bootstrap/secrets.auto.tfvars"

[[ "$(id -un)" == "${SV_LAB_USER:-bot}" ]] || { echo "Run this as ${SV_LAB_USER:-bot} on the mini, not as $(id -un)."; exit 1; }
[[ ! -e "$OUT" ]] || { echo "$OUT already exists; move it aside first if you mean to replace it."; exit 1; }
for t in stripe mkcert openssl; do command -v "$t" >/dev/null || { echo "$t is missing (scripts/Brewfile)."; exit 1; }; done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

password() { openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-32; }

ask() {
  local prompt="$1" prefix="$2" value
  read -rsp "$prompt: " value
  echo >&2
  [[ "$value" == "$prefix"* ]] || { echo "Expected a value starting with $prefix; stopping." >&2; exit 1; }
  printf '%s' "$value"
}

{
  echo "# Written by scripts/secrets/new-secrets-tfvars.sh on $(date -u +%Y-%m-%d). Never commit this file."
  echo "environments = {"
} >"$TMP/out"

for env in dev prod; do
  echo "Stripe sandbox sorted-vintage-$env (Developers > API keys, test mode):"
  sk="$(ask "  Secret key" "sk_test_")"
  pk="$(ask "  Publishable key" "pk_test_")"
  whsec="$(stripe listen --project-name "sv-$env" --print-secret 2>/dev/null)"
  [[ "$whsec" == whsec_* ]] || { echo "Could not read the webhook signing secret for sv-$env; run: stripe login --project-name sv-$env"; exit 1; }
  {
    echo "  $env = {"
    echo "    stripe_secret_key      = \"$sk\""
    echo "    stripe_publishable_key = \"$pk\""
    echo "    stripe_webhook_secret  = \"$whsec\""
    echo "    db_passwords = {"
    for db in listings orders payments notifications; do
      printf '      %-13s = "%s"\n' "$db" "$(password)"
    done
    echo "    }"
    echo "  }"
  } >>"$TMP/out"
  unset sk pk whsec
done
echo "}" >>"$TMP/out"

mkcert -cert-file "$TMP/tls.crt" -key-file "$TMP/tls.key" "*.sortedvtg.lan" "sortedvtg.lan" >/dev/null 2>&1
{
  echo
  echo "tls_certificate = <<EOT"
  cat "$TMP/tls.crt"
  echo "EOT"
  echo
  echo "tls_private_key = <<EOT"
  cat "$TMP/tls.key"
  echo "EOT"
} >>"$TMP/out"

install -m 600 "$TMP/out" "$OUT"
echo "Wrote $OUT (mode 600). No values were shown."
"$ROOT/scripts/secrets/add-garage-secrets.sh"
"$ROOT/scripts/secrets/add-keycloak-secrets.sh"
echo "The mkcert CA is in $(mkcert -CAROOT); trusting it on the Air is part of docs/runbooks/lab-session.md (T015)."
