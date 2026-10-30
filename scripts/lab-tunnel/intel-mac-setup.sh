#!/usr/bin/env bash
# Run on the Intel MacBook Pro, as the user Jenkins runs as. Idempotent.
# Sets up the Jenkins controller on loopback only, and a reverse SSH tunnel to the Mac mini
# that carries Jenkins (8081) and this Mac's SSH (2222) to the mini's loopback.
# Nothing on this Mac listens on the home network; see docs/runbooks/intel-mac-jenkins.md.
#   MINI       mini host name on the LAN (default: ricomillzs-Mac-mini.local)
#   MINI_USER  account on the mini that accepts the tunnel key (default: ricomillz)
set -euo pipefail

MINI="${MINI:-ricomillzs-Mac-mini.local}"
MINI_USER="${MINI_USER:-ricomillz}"
KEY="$HOME/.ssh/sv_lab_tunnel"
AGENTS="$HOME/Library/LaunchAgents"
JENKINS_PLIST="$AGENTS/com.sortedvintage.jenkins.plist"
TUNNEL_PLIST="$AGENTS/com.sortedvintage.lab-tunnel.plist"
LOGS="$HOME/Library/Logs/sorted-vintage"

command -v brew >/dev/null || { echo "Homebrew is required"; exit 1; }
mkdir -p "$AGENTS" "$LOGS" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

echo "Jenkins controller"
brew list --formula jenkins-lts >/dev/null 2>&1 || brew install jenkins-lts
# The Homebrew service would start a second copy; this LaunchAgent replaces it.
brew services stop jenkins-lts >/dev/null 2>&1 || true
JENKINS_BIN="$(brew --prefix)/opt/jenkins-lts/bin/jenkins-lts"
cat >"$JENKINS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.sortedvintage.jenkins</string>
  <key>ProgramArguments</key>
  <array>
    <string>$JENKINS_BIN</string>
    <string>--httpListenAddress=127.0.0.1</string>
    <string>--httpPort=8080</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>JENKINS_HOME</key><string>$HOME/.jenkins</string>
    <key>CASC_JENKINS_CONFIG</key><string>$HOME/.jenkins/casc.yaml</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOGS/jenkins.log</string>
  <key>StandardErrorPath</key><string>$LOGS/jenkins.log</string>
</dict>
</plist>
EOF

CASC="$(cd "$(dirname "$0")/../.." && pwd)/jenkins/casc.yaml"
if [[ -f "$CASC" ]]; then
  mkdir -p "$HOME/.jenkins" && cp "$CASC" "$HOME/.jenkins/casc.yaml"
  echo "  copied jenkins/casc.yaml to ~/.jenkins/"
fi

echo "Tunnel key"
[[ -f "$KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "sv-lab-tunnel@$(hostname -s)" -f "$KEY"

echo "Reverse tunnel to $MINI_USER@$MINI"
cat >"$TUNNEL_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.sortedvintage.lab-tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/ssh</string>
    <string>-N</string>
    <string>-i</string><string>$KEY</string>
    <string>-o</string><string>IdentitiesOnly=yes</string>
    <string>-o</string><string>BatchMode=yes</string>
    <string>-o</string><string>ExitOnForwardFailure=yes</string>
    <string>-o</string><string>ServerAliveInterval=30</string>
    <string>-o</string><string>ServerAliveCountMax=3</string>
    <string>-o</string><string>StrictHostKeyChecking=accept-new</string>
    <string>-R</string><string>127.0.0.1:8081:127.0.0.1:8080</string>
    <string>-R</string><string>127.0.0.1:2222:127.0.0.1:22</string>
    <string>$MINI_USER@$MINI</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardErrorPath</key><string>$LOGS/lab-tunnel.log</string>
</dict>
</plist>
EOF

for plist in "$JENKINS_PLIST" "$TUNNEL_PLIST"; do
  launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
done

echo
echo "Done. Next, on the Mac mini, authorize the tunnel key (prints nothing secret):"
echo "  scripts/lab-tunnel/authorize-tunnel-key.sh '$(cat "$KEY.pub")'"
echo
echo "Then on this Mac: System Settings → Network → Firewall → on, Options → Block all incoming connections."
echo "Remote Login can stay on; with the firewall blocking incoming connections it is reachable only through the tunnel."
