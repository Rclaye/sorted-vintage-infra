#!/usr/bin/env bash
# Rewrites stripe_webhook_secret for each environment in ~/sv-terraform/secrets.auto.tfvars on the
# lab host, as bot: stripe listen --print-secret with that environment's stripe_secret_key from the
# same file, which is the key the in-cluster forwarder uses (research R4). Each Stripe key has its own
# listen signing secret, so a secret read through `stripe login` does not verify the forwarder's
# events. Nothing secret is printed; the file keeps mode 600. Apply with the Jenkins pipeline after.
# From the workstation:
#   ssh lab '~/Sorted-Vintage/src/sorted-vintage-infra/scripts/secrets/refresh-webhook-secrets.sh'
set -euo pipefail
umask 077

FILE="${SV_TF_DIR:-$HOME/sv-terraform}/secrets.auto.tfvars"
[[ "$(id -un)" == "${SV_LAB_USER:-bot}" ]] || { echo "Run this as ${SV_LAB_USER:-bot} on the lab host."; exit 1; }
[[ -f "$FILE" ]] || { echo "$FILE does not exist."; exit 1; }
command -v stripe >/dev/null || { echo "stripe is missing (scripts/Brewfile)."; exit 1; }

# The value of KEY inside the "  ENV = {" block.
value_in() {
  awk -v env="$1" -v key="$2" '
    $0 ~ "^  " env " = \\{" { inside = 1; next }
    inside && /^  \}/       { inside = 0 }
    inside && $1 == key     { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v; exit }
  ' "$FILE"
}

tmp="$(mktemp "${FILE}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cp "$FILE" "$tmp"

for env in dev prod; do
  sk="$(value_in "$env" stripe_secret_key)"
  [[ "$sk" == sk_test_* ]] || { echo "No test secret key for $env in $FILE."; exit 1; }
  whsec="$(stripe listen --api-key "$sk" --print-secret 2>/dev/null)"
  [[ "$whsec" == whsec_* ]] || { echo "Could not read the webhook signing secret for $env."; exit 1; }
  old="$(value_in "$env" stripe_webhook_secret)"
  if [[ "$old" == "$whsec" ]]; then
    echo "$env: already current"
  else
    WHSEC="$whsec" awk -v env="$env" '
      $0 ~ "^  " env " = \\{"                  { inside = 1 }
      inside && /^  \}/                         { inside = 0 }
      inside && $1 == "stripe_webhook_secret"   { sub(/"[^"]*"/, "\"" ENVIRON["WHSEC"] "\"") }
      { print }
    ' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp"
    [[ "$(FILE="$tmp" value_in "$env" stripe_webhook_secret)" == "$whsec" ]] \
      || { echo "$env: the new value did not land in the file; nothing was changed."; exit 1; }
    echo "$env: updated"
  fi
  unset sk whsec old
done

chmod 600 "$tmp"
mv "$tmp" "$FILE"
trap - EXIT
echo "Done. Run the Jenkins pipeline (infra-terraform) and approve the plan: it changes the Secret stripe in sv-dev and sv-prod."
