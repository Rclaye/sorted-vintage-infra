#!/usr/bin/env bash
# Run on the Mac mini. Authorizes the Jenkins controller's agent key from the MacBook Air.
# The key may run commands (the agent needs that) but gets no port, agent or X11 forwarding and no pty.
# Usage: authorize-agent-key.sh 'ssh-ed25519 AAAA... sv-jenkins-agent@host'
set -euo pipefail

pub="${1:?usage: $0 '<contents of ~/.ssh/sv_jenkins_agent.pub from the Air>'}"
[[ "$pub" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ .*)?$ ]] || { echo "not an ed25519 public key"; exit 1; }

AK="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$AK" && chmod 600 "$AK"

key_body="$(awk '{print $2}' <<<"$pub")"
if grep -qF "$key_body" "$AK"; then
  echo "Key already present in $AK; leaving it unchanged."
else
  printf 'restrict %s\n' "$pub" >>"$AK"
  echo "Added the Jenkins agent key to $AK (restrict: no forwarding, no pty)."
fi
mkdir -p "$HOME/jenkins-agent"
command -v java >/dev/null 2>&1 || echo "Java is not on PATH here; install it (brew bundle --file scripts/Brewfile) before the agent connects."
