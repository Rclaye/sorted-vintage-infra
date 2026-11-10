#!/usr/bin/env bash
# Run on the workstation from your everyday (admin) account. Idempotent; asks for your password.
# Installs the Jenkins controller bound to 127.0.0.1:8080 (nothing listens on the local network),
# running as the workstation's dedicated standard account (not the lab host's admin account),
# and creates the key that account uses to start the build agent on the lab host over SSH, as the lab host's bot.
# See docs/runbooks/jenkins.md and research R15.
# Set both in scripts/lab/local.env (git-ignored; copy scripts/lab/local.env.example), per ADR-0009:
#   SV_JENKINS_USER  the workstation's Jenkins account
#   SV_LAB_HOST      the lab host's hostname as written in your known_hosts
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -f "$REPO/scripts/lab/local.env" ]]; then set -a; . "$REPO/scripts/lab/local.env"; set +a; fi
JUSER="${SV_JENKINS_USER:?set SV_JENKINS_USER in scripts/lab/local.env (see local.env.example)}"
MINI_HOST="${SV_LAB_HOST:?set SV_LAB_HOST in scripts/lab/local.env (see local.env.example)}"
LABEL=com.sortedvintage.jenkins
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CASC="$REPO/jenkins/casc.yaml"
PLUGINS="$REPO/jenkins/plugins.txt"
# Jenkins Plugin Installation Manager, pinned and checksum-checked (T103).
PIM_VERSION=2.15.0
PIM_SHA256=a86853ec2e2933f37a4b471ba65099b61e03c87a80c2ef8fe2315eb135672d43

command -v brew >/dev/null || { echo "Homebrew is required"; exit 1; }
[[ -f "$CASC" && -f "$PLUGINS" ]] || { echo "Run this from a clone that has jenkins/casc.yaml and jenkins/plugins.txt."; exit 1; }
[[ "$(id -un)" != "$JUSER" ]] || { echo "Run this from your everyday account, not as $JUSER."; exit 1; }
id "$JUSER" >/dev/null 2>&1 || { echo "No account '$JUSER' on this Mac. Create a standard account first (System Settings > Users & Groups)."; exit 1; }
if dsmemberutil checkmembership -U "$JUSER" -G admin | grep -q 'is a member'; then
  echo "'$JUSER' is an admin. Jenkins must run as a standard account; change it in System Settings > Users & Groups."
  exit 1
fi
JHOME="$(dscl . -read "/Users/$JUSER" NFSHomeDirectory | awk '{print $2}')"
KEY="$JHOME/.ssh/sv_jenkins_agent"
LOGS="$JHOME/Library/Logs/sorted-vintage"
# Run as the Jenkins account from /, because it may not enter your (closed) current folder.
as_j() { (cd / && sudo -u "$JUSER" -H "$@"); }

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
sudo install -o "$JUSER" -g staff -m 600 "$CASC" "$JHOME/.jenkins/casc.yaml"
echo "  copied jenkins/casc.yaml to $JHOME/.jenkins/"

JAVA="$(brew --prefix openjdk@21)/bin/java"
WAR="$(brew --prefix)/opt/jenkins-lts/libexec/jenkins.war"
[[ -x "$JAVA" && -f "$WAR" ]] || { echo "Missing $JAVA or $WAR after installing jenkins-lts."; exit 1; }

# The admin password: random, in a file only $JUSER can read; casc.yaml reads it at start.
ADMIN_PW="$JHOME/.jenkins/sv-admin-password"
if ! sudo test -s "$ADMIN_PW"; then
  as_j /bin/sh -c "umask 077; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 > '$ADMIN_PW'"
  echo "  created the admin password file (readable by $JUSER only)"
fi

echo "Plugins"
tmpd="$(mktemp -d)"
curl -fsSL -o "$tmpd/pim.jar" "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/$PIM_VERSION/jenkins-plugin-manager-$PIM_VERSION.jar"
echo "$PIM_SHA256  $tmpd/pim.jar" | shasum -a 256 -c - >/dev/null || { echo "Plugin manager checksum mismatch; stopping."; rm -rf "$tmpd"; exit 1; }
sudo install -o "$JUSER" -g staff -m 644 "$tmpd/pim.jar" "$JHOME/.jenkins/jenkins-plugin-manager.jar"
sudo install -o "$JUSER" -g staff -m 644 "$PLUGINS" "$JHOME/.jenkins/plugins.txt"
rm -rf "$tmpd"
echo "  downloading the plugins in jenkins/plugins.txt and their dependencies (a few minutes)"
if ! as_j "$JAVA" -jar "$JHOME/.jenkins/jenkins-plugin-manager.jar" --war "$WAR" \
     --plugin-download-directory "$JHOME/.jenkins/plugins" --plugin-file "$JHOME/.jenkins/plugins.txt" \
     > "${TMPDIR:-/tmp}/sv-plugin-install.log" 2>&1; then
  echo "Plugin installation failed. Last lines of the log:"; tail -20 "${TMPDIR:-/tmp}/sv-plugin-install.log"; exit 1
fi
echo "  installed $(as_j ls "$JHOME/.jenkins/plugins" | grep -c '\.jpi$') plugins"

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
    <string>$JAVA</string>
    <string>-Djenkins.install.runSetupWizard=false</string>
    <string>-jar</string>
    <string>$WAR</string>
    <string>--httpListenAddress=127.0.0.1</string>
    <string>--httpPort=8080</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$JHOME</string>
    <key>JENKINS_HOME</key><string>$JHOME/.jenkins</string>
    <key>CASC_JENKINS_CONFIG</key><string>$JHOME/.jenkins/casc.yaml</string>
    <key>SV_AGENT_KEY_FILE</key><string>$KEY</string>
    <key>SV_ADMIN_PASSWORD_FILE</key><string>$ADMIN_PW</string>
    <key>SV_LAB_HOST</key><string>$MINI_HOST</string>
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
# Reload the service. bootout returns before a running Jenkins has stopped, and bootstrap fails
# ("5: Input/output error") while the old one is still loaded, so wait for it to go.
if sudo launchctl print "system/$LABEL" >/dev/null 2>&1; then
  sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
  for _ in $(seq 1 60); do
    sudo launchctl print "system/$LABEL" >/dev/null 2>&1 || break
    sleep 1
  done
fi
sudo launchctl bootstrap system "$PLIST"
echo "  LaunchDaemon $LABEL runs Jenkins as $JUSER; it does not start at boot"

echo "Agent key"
sudo test -f "$KEY" || as_j ssh-keygen -q -t ed25519 -N "" -C "sv-jenkins-agent@$(hostname -s)" -f "$KEY"
# Trust the lab host's host key you already verified, rather than accepting one on first use.
if entry="$(ssh-keygen -F "$MINI_HOST" -f "$HOME/.ssh/known_hosts" | grep -v '^#')" && [[ -n "$entry" ]]; then
  if ! as_j ssh-keygen -F "$MINI_HOST" -f "$JHOME/.ssh/known_hosts" >/dev/null 2>&1; then
    printf '%s\n' "$entry" | as_j tee -a "$JHOME/.ssh/known_hosts" >/dev/null
    as_j chmod 600 "$JHOME/.ssh/known_hosts"
  fi
  echo "  $JUSER trusts the lab host's host key from your known_hosts"
else
  echo "  WARNING: $MINI_HOST is not in your known_hosts; run 'ssh lab true' once, then rerun this script."
fi

echo
echo "Done. Jenkins does not start at boot; start it at the beginning of a lab session with:"
echo "  sudo launchctl kickstart system/$LABEL"
echo "and open http://localhost:8080. Sign in as admin; this copies the password to your clipboard:"
echo "  sudo cat $ADMIN_PW | pbcopy"
echo
echo "Next, from this account, authorize the agent key on the lab host as bot (prints nothing secret):"
echo "  ssh lab \"~/Sorted-Vintage/src/sorted-vintage-infra/scripts/jenkins/authorize-agent-key.sh '$(sudo cat "$KEY.pub")'\""
