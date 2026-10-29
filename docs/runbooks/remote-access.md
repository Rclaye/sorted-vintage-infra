# Runbook: Remote access to the lab

The Mac mini (`mac-mini`) is reached over SSH from the MacBook Air: on the home network directly, or over Tailscale when away. No ports are open on the home router.

## Connect

```bash
ssh mac-mini
```

If this hangs, check that the mini is awake; away from home, check that both machines show as connected in Tailscale.

## Reach web UIs on the mini

Port-forward on the mini, tunnel from the Air, then open `http://localhost:<port>` in a browser on the Air.

| UI | On the mini | Tunnel from the Air |
| --- | --- | --- |
| Argo CD | `kubectl -n argocd port-forward svc/argocd-server 8080:443` | `ssh -L 8080:localhost:8080 mac-mini` |
| Grafana | `kubectl -n monitoring port-forward svc/grafana 3000:80` | `ssh -L 3000:localhost:3000 mac-mini` |

(The namespaces and service names are confirmed in Sprint 1.)

Editors: VS Code's Remote-SSH extension connects to `mac-mini` and works on the mini's files directly.

## Sessions

The lab runs only while I am working. The mini is kept awake with Amphetamine during a session and can be off otherwise. One-command start and stop (with a backup on stop) arrive in Sprint 1.

## If the mini stops responding

1. Check that it is awake and on the network (and, if used, online in Tailscale).
2. If SSH fails but the mini is up, use Screen Sharing (`vnc://mac-mini`) or work on it directly.
3. If the cluster does not come back cleanly after a restart, rebuild it from Git; that is the rebuild drill anyway.
