# Runbook: Remote access to the lab

The Mac mini is reached over SSH from the MacBook Air: on the home network directly, or over Tailscale when away. No ports are open on the home router, and the mini accepts SSH keys only, no passwords.

The mini has two accounts (ADR-0008):

| From the Air | Mini account | Use it for |
| --- | --- | --- |
| `ssh mac-mini-lab` | `bot`, standard | Everything in the lab: Docker, Kind, Terraform, `make`, the Jenkins agent |
| `ssh mac-mini` | `ricomillz`, admin | Homebrew installs and system settings only |

`bot` must be logged in at the mini's screen during a session, because Docker Desktop runs only inside a desktop session. To reach another account at the screen, use fast user switching, not Log Out.

## Connect

```bash
ssh mac-mini-lab
```

If this hangs, check that the mini is awake; away from home, check that both machines show as connected in Tailscale.

## Reach web UIs in the lab

From Sprint 1, one connection carries the cluster's web UIs:

```bash
ssh -N -L 8443:127.0.0.1:443 mac-mini-lab
```

Argo CD, Grafana, Mailpit and the marketplace are then at `https://<host>.sortedvtg.lan:8443` (see [lab-session.md](./lab-session.md)). Jenkins runs on the Air itself, at `http://localhost:8080` ([jenkins.md](./jenkins.md)).

Editors: VS Code's Remote-SSH extension connects to `mac-mini-lab` and works on `bot`'s files directly.

## Sessions

The lab runs only while I am working. The mini is kept awake with Amphetamine during a session and can be off otherwise. One-command start and stop arrive in Sprint 1: `make up` and `make down`, which checks that the database backups are current before stopping.

## Sharing the mini with LocalMind

LocalMind also runs on the mini, natively with Ollama. Do not run both at once: an 8B model takes 5–6 GB and the cluster up to 12 GB, out of 16 GB. LocalMind runs in the admin account's desktop session, so quit Ollama there before starting a Sorted Vintage session.

## If the mini stops responding

1. Check that it is awake and on the network (and, if used, online in Tailscale).
2. If SSH fails but the mini is up, use Screen Sharing (`vnc://mac-mini`) or work on it directly.
3. If the cluster does not come back cleanly after a restart, rebuild it from Git; that is the rebuild drill anyway.
