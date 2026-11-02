#!/usr/bin/env bash
# Run on the Mac mini as bot, the standard account that owns the lab (from the Air: ssh mac-mini-lab "...").
# Authorizes the agent key of the Jenkins controller, which runs on the MacBook Air as the Air's ricomillz account.
# Never run it as the mini's admin account: the agent must not log in with admin rights.
# The key may run commands (the agent needs that) but gets no port, agent or X11 forwarding and no pty.
# Usage: authorize-agent-key.sh 'ssh-ed25519 AAAA... sv-jenkins-agent@host'
set -euo pipefail

[[ "$(id -un)" == "${SV_LAB_USER:-bot}" ]] || { echo "Run this as ${SV_LAB_USER:-bot} on the mini, not as $(id -un)."; exit 1; }

pub="${1:?usage: $0 '<contents of /Users/ricomillz/.ssh/sv_jenkins_agent.pub from the Air>'}"
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
JAVA=/opt/homebrew/opt/openjdk@21/bin/java
[[ -x "$JAVA" ]] || echo "$JAVA is missing; install openjdk@21 as the mini's admin (brew bundle --file scripts/Brewfile) before the agent connects."
