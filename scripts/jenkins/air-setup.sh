#!/usr/bin/env bash
# Run on the MacBook Air. Idempotent.
# Installs the Jenkins controller bound to 127.0.0.1:8080 (nothing listens on the home network)
# and creates the key the controller uses to start its build agent on the Mac mini over SSH.
# See docs/runbooks/jenkins.md.
set -euo pipefail

KEY="$HOME/.ssh/sv_jenkins_agent"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/com.sortedvintage.jenkins.plist"
LOGS="$HOME/Library/Logs/sorted-vintage"
CASC="$(cd "$(dirname "$0")/../.." && pwd)/jenkins/casc.yaml"

command -v brew >/dev/null || { echo "Homebrew is required"; exit 1; }
mkdir -p "$AGENTS" "$LOGS" "$HOME/.ssh" "$HOME/.jenkins"
chmod 700 "$HOME/.ssh"

echo "Jenkins controller"
brew list --formula jenkins-lts >/dev/null 2>&1 || brew install jenkins-lts
# The Homebrew service would start a second copy; this LaunchAgent replaces it and pins the bind address.
brew services stop jenkins-lts >/dev/null 2>&1 || true
if [[ -f "$CASC" ]]; then
  cp "$CASC" "$HOME/.jenkins/casc.yaml"
  echo "  copied jenkins/casc.yaml to ~/.jenkins/"
fi
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.sortedvintage.jenkins</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(brew --prefix)/opt/jenkins-lts/bin/jenkins-lts</string>
    <string>--httpListenAddress=127.0.0.1</string>
    <string>--httpPort=8080</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>JENKINS_HOME</key><string>$HOME/.jenkins</string>
    <key>CASC_JENKINS_CONFIG</key><string>$HOME/.jenkins/casc.yaml</string>
    <key>SV_AGENT_KEY_FILE</key><string>$KEY</string>
  </dict>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>$LOGS/jenkins.log</string>
  <key>StandardErrorPath</key><string>$LOGS/jenkins.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Agent key"
[[ -f "$KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "sv-jenkins-agent@$(hostname -s)" -f "$KEY"

echo
echo "Done. Jenkins does not start at login; start it at the beginning of a lab session with:"
echo "  launchctl kickstart gui/$(id -u)/com.sortedvintage.jenkins"
echo "and open http://localhost:8080."
echo
echo "Next, on the Mac mini, authorize the agent key (prints nothing secret):"
echo "  scripts/jenkins/authorize-agent-key.sh '$(cat "$KEY.pub")'"
