#!/usr/bin/env bash
# Run on the MacBook Air from your everyday (admin) account. Idempotent; asks for your password.
# Installs the Jenkins controller bound to 127.0.0.1:8080 (nothing listens on the home network),
# running as the Air's dedicated standard account (default ricomillz, not the mini's login of the same name),
# and creates the key that account uses to start the build agent on the Mac mini over SSH.
# See docs/runbooks/jenkins.md and research R15.
#   SV_JENKINS_USER  the Air's Jenkins account (default: ricomillz)
#   SV_MINI_HOST     the mini's hostname as written in your known_hosts (default: ricomillzs-Mac-mini.local)
set -euo pipefail

JUSER="${SV_JENKINS_USER:-ricomillz}"
MINI_HOST="${SV_MINI_HOST:-ricomillzs-Mac-mini.local}"
LABEL=com.sortedvintage.jenkins
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CASC="$(cd "$(dirname "$0")/../.." && pwd)/jenkins/casc.yaml"

command -v brew >/dev/null || { echo "Homebrew is required"; exit 1; }
[[ "$(id -un)" != "$JUSER" ]] || { echo "Run this from your everyday account, not as $JUSER."; exit 1; }
id "$JUSER" >/dev/null 2>&1 || { echo "No account '$JUSER' on this Mac. Create a standard account first (System Settings > Users & Groups)."; exit 1; }
if dsmemberutil checkmembership -U "$JUSER" -G admin | grep -q 'is a member'; then
  echo "'$JUSER' is an admin. Jenkins must run as a standard account; change it in System Settings > Users & Groups."
  exit 1
fi
JHOME="$(dscl . -read "/Users/$JUSER" NFSHomeDirectory | awk '{print $2}')"
KEY="$JHOME/.ssh/sv_jenkins_agent"
LOGS="$JHOME/Library/Logs/sorted-vintage"
as_j() { sudo -u "$JUSER" -H "$@"; }

echo "Your home folder"
if [[ -n "$(find "$HOME" -maxdepth 0 -perm -040)" ]]; then
  echo "  WARNING: $HOME is readable by other accounts, including $JUSER. Run: chmod 700 ~"
else
  echo "  $HOME is closed to other accounts"
fi

echo "Jenkins controller"
brew list --formula jenkins-lts >/dev/null 2>&1 || brew install jenkins-lts
# The Homebrew service would start a second copy as you; the LaunchDaemon below replaces it.
brew services stop jenkins-lts >/dev/null 2>&1 || true
as_j mkdir -p "$JHOME/.jenkins" "$JHOME/.ssh" "$LOGS"
as_j chmod 700 "$JHOME/.jenkins" "$JHOME/.ssh"
if [[ -f "$CASC" ]]; then
  sudo install -o "$JUSER" -g staff -m 600 "$CASC" "$JHOME/.jenkins/casc.yaml"
  echo "  copied jenkins/casc.yaml to $JHOME/.jenkins/"
fi

tmp="$(mktemp)"
cat >"$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>UserName</key><string>$JUSER</string>
  <key>GroupName</key><string>staff</string>
  <key>Umask</key><integer>63</integer>
  <key>ProgramArguments</key>
  <array>
    <string>$(brew --prefix)/opt/jenkins-lts/bin/jenkins-lts</string>
    <string>--httpListenAddress=127.0.0.1</string>
    <string>--httpPort=8080</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$JHOME</string>
    <key>JENKINS_HOME</key><string>$JHOME/.jenkins</string>
    <key>CASC_JENKINS_CONFIG</key><string>$JHOME/.jenkins/casc.yaml</string>
    <key>SV_AGENT_KEY_FILE</key><string>$KEY</string>
  </dict>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>$LOGS/jenkins.log</string>
  <key>StandardErrorPath</key><string>$LOGS/jenkins.log</string>
</dict>
</plist>
EOF
plutil -lint "$tmp" >/dev/null
sudo install -o root -g wheel -m 644 "$tmp" "$PLIST"
rm -f "$tmp"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
echo "  LaunchDaemon $LABEL runs Jenkins as $JUSER; it does not start at boot"

echo "Agent key"
sudo test -f "$KEY" || as_j ssh-keygen -q -t ed25519 -N "" -C "sv-jenkins-agent@$(hostname -s)" -f "$KEY"
# Trust the mini's host key you already verified, rather than accepting one on first use.
if entry="$(ssh-keygen -F "$MINI_HOST" -f "$HOME/.ssh/known_hosts" | grep -v '^#')" && [[ -n "$entry" ]]; then
  if ! as_j ssh-keygen -F "$MINI_HOST" -f "$JHOME/.ssh/known_hosts" >/dev/null 2>&1; then
    printf '%s\n' "$entry" | as_j tee -a "$JHOME/.ssh/known_hosts" >/dev/null
    as_j chmod 600 "$JHOME/.ssh/known_hosts"
  fi
  echo "  $JUSER trusts the mini's host key from your known_hosts"
else
  echo "  WARNING: $MINI_HOST is not in your known_hosts; run 'ssh mac-mini true' once, then rerun this script."
fi

echo
echo "Done. Jenkins does not start at boot; start it at the beginning of a lab session with:"
echo "  sudo launchctl kickstart system/$LABEL"
echo "and open http://localhost:8080."
echo
echo "Next, on the Mac mini, as its own ricomillz login, authorize the agent key (prints nothing secret):"
echo "  scripts/jenkins/authorize-agent-key.sh '$(sudo cat "$KEY.pub")'"
