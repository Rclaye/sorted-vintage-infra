#!/usr/bin/env bash
# Run on the Mac mini. Authorizes the Intel Mac's tunnel key for remote port forwards only:
# no shell, no commands, no agent or X11 forwarding, and listens limited to 127.0.0.1:8081 and 127.0.0.1:2222.
# Usage: authorize-tunnel-key.sh 'ssh-ed25519 AAAA... sv-lab-tunnel@host'
set -euo pipefail

pub="${1:?usage: $0 '<contents of ~/.ssh/sv_lab_tunnel.pub from the Intel Mac>'}"
[[ "$pub" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ .*)?$ ]] || { echo "not an ed25519 public key"; exit 1; }

AK="$HOME/.ssh/authorized_keys"
# permitopen points local (-L) forwards at the discard port, so the key cannot reach anything through the mini.
OPTS='restrict,port-forwarding,permitlisten="127.0.0.1:8081",permitlisten="127.0.0.1:2222",permitopen="127.0.0.1:9",command="/usr/bin/false"'
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$AK" && chmod 600 "$AK"

key_body="$(awk '{print $2}' <<<"$pub")"
if grep -qF "$key_body" "$AK"; then
  echo "Key already present in $AK; leaving it unchanged."
else
  printf '%s %s\n' "$OPTS" "$pub" >>"$AK"
  echo "Added the tunnel key to $AK with forward-only restrictions."
fi
echo "The tunnel's ports bind to this Mac's loopback only (sshd GatewayPorts is off by default)."
