# Runbook: Remote access to the lab

The Mac mini (`mac-mini`) is reached over SSH from the MacBook Air: on the home network directly, or over Tailscale when away. No ports are open on the home router.

## Connect

```bash
ssh mac-mini
```

If this hangs, check that the mini is awake; away from home, check that both machines show as connected in Tailscale.

## Reach web UIs in the lab

From Sprint 1, one connection carries everything:

```bash
ssh -N mac-mini
```

With the `LocalForward` lines from [intel-mac-jenkins.md](./intel-mac-jenkins.md#one-time-setup) in `~/.ssh/config`, this forwards:

- the cluster's ingress, at `https://<host>.sortedvtg.lan:8443` (Argo CD, Grafana, Mailpit and the marketplace; see [lab-session.md](./lab-session.md));
- Jenkins on the Intel Mac, at `http://localhost:8081`, through the lab tunnel.

`ssh intel-mac` opens a shell on the Intel Mac through the same tunnel. The Intel Mac has no port open on the home network.

Editors: VS Code's Remote-SSH extension connects to `mac-mini` and works on the mini's files directly.

## Sessions

The lab runs only while I am working. The mini is kept awake with Amphetamine during a session and can be off otherwise. One-command start and stop arrive in Sprint 1: `make up` and `make down`, which checks that the database backups are current before stopping.

## Sharing the mini with LocalMind

LocalMind also runs on the mini, natively with Ollama. Do not run both at once: an 8B model takes 5–6 GB and the cluster up to 12 GB, out of 16 GB. Quit Ollama before starting a Sorted Vintage session.

## If the mini stops responding

1. Check that it is awake and on the network (and, if used, online in Tailscale).
2. If SSH fails but the mini is up, use Screen Sharing (`vnc://mac-mini`) or work on it directly.
3. If the cluster does not come back cleanly after a restart, rebuild it from Git; that is the rebuild drill anyway.
