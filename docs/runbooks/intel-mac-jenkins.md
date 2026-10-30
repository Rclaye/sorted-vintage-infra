# Runbook: Jenkins on the Intel Mac, reached through the lab tunnel

The Intel MacBook Pro runs the Jenkins controller and nothing else (SonarQube is SonarQube Cloud; see [research R15](../../specs/001-marketplace-local-cloud/research.md#r15-ci-hosts-and-how-they-are-reached)). Nothing on the Intel Mac listens on the home network. It makes one outbound SSH connection to the Mac mini, and that connection carries Jenkins and the Intel Mac's own SSH back to the mini's loopback interface. From the Air, you reach both through the SSH connection to the mini you already use.

```text
MacBook Air ──ssh (existing, key-only)──▶ Mac mini ◀──ssh -R (outbound from Intel Mac)── Intel MacBook Pro
  localhost:8081 ──-L──▶ 127.0.0.1:8081 ═══════════════════════════════════════▶ 127.0.0.1:8080 Jenkins
  ssh intel-mac ──ProxyJump──▶ 127.0.0.1:2222 ═════════════════════════════════▶ 127.0.0.1:22   sshd
```

What makes it closed to the home network:

- Jenkins binds `127.0.0.1:8080` only.
- The macOS firewall on the Intel Mac blocks all incoming connections, which covers Remote Login and every other sharing service. Loopback traffic from the tunnel is not affected.
- The tunnel's ports on the mini bind to `127.0.0.1` (sshd's `GatewayPorts` is off by default).
- The tunnel key on the mini can only open those two listens: no shell, no commands, no other forwards.
- The Jenkins controller starts the mini's build agent by SSH, outbound from the Intel Mac, so no agent port (50000) is opened. GitHub cannot reach Jenkins, so jobs poll Git instead of using webhooks.

The tunnel works whenever both Macs are on. The Intel Mac retries every 30 seconds while the mini is off.

## One-time setup

**1. On the Intel Mac**, from a clone of this repository, logged in as the user Jenkins will run as:

```bash
scripts/lab-tunnel/intel-mac-setup.sh
```

It installs `jenkins-lts`, replaces the Homebrew service with a LaunchAgent bound to loopback, creates the tunnel key `~/.ssh/sv_lab_tunnel`, starts the tunnel LaunchAgent, and prints the command for step 2.

LaunchAgents run while the user is logged in. Turn on automatic login for that user (System Settings → Users & Groups) so Jenkins and the tunnel come back after a restart.

**2. On the Mac mini**, paste the command step 1 printed:

```bash
scripts/lab-tunnel/authorize-tunnel-key.sh '<the public key step 1 printed>'
```

**3. On the Intel Mac**, turn the firewall on: System Settings → Network → Firewall → on, then Options → **Block all incoming connections**. You can leave Remote Login on.

**4. On the Air**, add to `~/.ssh/config`. Keep the existing `HostName`, `User` and `IdentityFile` lines under `mac-mini`, and set `User` under `intel-mac` to your Intel Mac account:

```text
Host mac-mini
    LocalForward 8443 127.0.0.1:443
    LocalForward 8081 127.0.0.1:8081

Host intel-mac
    HostName 127.0.0.1
    Port 2222
    HostKeyAlias intel-mac
    User <intel-mac-user>
    ProxyJump mac-mini
```

Then copy your Air key to the Intel Mac through the tunnel: `ssh-copy-id intel-mac`.

## Daily use

Open the lab connection from the Air and leave it running:

```bash
ssh -N mac-mini
```

- Jenkins: `http://localhost:8081`
- Marketplace, Argo CD, Grafana, Mailpit: `https://<host>.sortedvtg.lan:8443` (see [lab-session.md](./lab-session.md))
- A shell on the Intel Mac: `ssh intel-mac`

## Check it is closed

From the mini, against the Intel Mac's LAN name. Both must fail:

```bash
nc -z -G 2 <intel-mac-name>.local 22
nc -z -G 2 <intel-mac-name>.local 8080
```

On the mini, `lsof -nP -iTCP:8081 -sTCP:LISTEN` and `lsof -nP -iTCP:2222 -sTCP:LISTEN` must show `127.0.0.1` only. `verify_sprint1.sh` runs these checks when `INTEL_LAN_HOST` is set.

## When something fails

| Symptom | Check |
| --- | --- |
| `localhost:8081` refuses | On the mini, is `127.0.0.1:8081` listening? If not, read `~/Library/Logs/sorted-vintage/lab-tunnel.log` on the Intel Mac. |
| The tunnel log shows `remote port forwarding failed` | An old tunnel still holds the port on the mini; it clears within 90 seconds (`ServerAliveCountMax` × `ServerAliveInterval`). |
| The tunnel log shows `Permission denied` | Step 2 was not run, or the key changed. Re-run step 2 with the current `~/.ssh/sv_lab_tunnel.pub`. |
| Jenkins is down | `~/Library/Logs/sorted-vintage/jenkins.log` on the Intel Mac. |
| You need the Intel Mac and the tunnel is down | Work on it directly, or temporarily turn off "Block all incoming connections" and use `ssh <user>@<intel-mac-name>.local`. Turn it back on afterwards. |
