# Sprint 1 Retrospective

## Outcome

Sprint 1 built the platform every user story runs on. One Terraform apply creates a single-node Kind cluster on the Mac mini and installs Argo CD; Argo CD installs everything else from `sorted-vintage-gitops`. A stub BFF made from the service template has travelled the full delivery path to dev and, through an approved promotion, to prod. Jenkins on the Air runs the infrastructure pipeline on the mini and ends every build by checking the live lab. `verify_sprint1.sh` passed every automated check on 2026-11-05, from the Air and as the Jenkins `verify` stage (build #4). Measured memory is about 6.1 GiB of pods against the plan's 9.5 GB estimate for the finished platform, so Sprint 2 starts with room to spare.

## Completed Work

### Ticket 1.1: Confirm the Research Decisions (T007, T008, T009)

- Kind survives `docker stop` / `docker start` with its data (API back in 4 s), so research R1 stands.
- Stripe: one signing secret per sandbox covers platform and connected-account events. New sandboxes refuse Accounts v1, so connected accounts moved to Accounts v2 (R17).
- Hooks for Terraform, ruff, hadolint and workflow schemas in all three repos (T007).

### Ticket 1.2: Cluster and Argo CD From One Terraform Apply (T010–T012)

- `terraform/cluster` creates the node with 80/443 bound to `127.0.0.1` only; `terraform/bootstrap` installs Argo CD, the root app and every bootstrap Secret from `secrets.auto.tfvars`.

### Ticket 1.3: Platform Add-Ons by Argo CD (T016–T025)

- cert-manager, Traefik, Garage, CloudNativePG with WAL archiving and daily backups to Garage, RabbitMQ, Mailpit, Keycloak with realms `sv-dev` and `sv-prod`, and Prometheus, Grafana, Loki, Tempo and the OTel Collector with Argo CD drift alerts.
- Each risky piece was spiked first on a throwaway cluster (`spikes.md`): Postgres restore from Garage, the observability round trip, Keycloak realms and re-import.
- Drift check: a Deployment deleted by hand was recreated by Argo CD 0.6 s later.

### Ticket 1.4: Policy at Admission and in CI (T026)

- Five Kyverno `ValidatingPolicy` objects in enforce mode: non-root, requests and limits, trusted images, no `hostPath` outside Garage's volumes, no spoofed `part-of` labels. The same policies run in CI on every gitops pull request.

### Ticket 1.5: Service Template and the Delivery Path (T027–T030, T080)

- Copier service template and the stub BFF. An app merge builds for arm64, runs Trivy, publishes to GHCR, and the `sv-deployer` GitHub App opens the dev tag pull request, which merges on green.
- Promotion to prod waits for approval in the `prod` environment; a `git revert` rollback went through the same gate (gitops #18).

### Ticket 1.6: Working Sessions (T013, T015)

- `make up`, `make down` (checks every database's archive is current before stopping) and `make backups-check`, with the lab-session runbook.
- Session check on 2026-11-05, run as `bot` over SSH with the full platform (28 apps):

| Check | Result |
| --- | --- |
| `make down` | 3 min 59 s: archives current for `keycloak-db` and both `pg` clusters, 60 s wait, current again, then the node stopped |
| `make up` | 75 s: API back in 10 s, all 28 apps Synced and Healthy 64 s later (limit 10 minutes) |
| Backups after the cycle | The same 9 `ScheduledBackup` backups as before; `make down` created none |
| Argo CD after the cycle | 28 Synced and Healthy, none out of sync |
| Prometheus history (what Grafana reads) | Samples from before the stop, back to 22:45 UTC, still queryable after `make up` |

### Ticket 1.7: Jenkins and SonarQube Cloud (T103–T107, T014)

- Jenkins on the Air as a dedicated standard account, on `127.0.0.1:8080` only, configured as code; the agent runs on the mini as `bot` over a restricted key.
- `infra-terraform`: fmt, validate, tfsec, plan, a manual approval before any apply, then `verify` runs the sprint's verify script on the mini (T107).
- Terraform state and `secrets.auto.tfvars` moved to `~/sv-terraform` on the mini, shared by `make rebuild` and Jenkins.
- SonarQube Cloud scans app pull requests after tests; the quality gate passed on app #4 (T105).
- Approval run, build #6 on 2026-11-05: a `terraform_data` record (infra #25) gave the pipeline a harmless change. The cluster plan showed `1 to add`, the build paused at `approve` until Richard clicked Apply, applied it (bootstrap: no changes), found all 28 apps healthy and passed `verify`.

### Ticket 1.8: Verify and Measure (T031, T032)

- `verify_sprint1.sh` brought up to date and given a local mode for the Jenkins agent (T031). Memory measured below (T032).

## Memory: Measured Against the Plan (T032)

Measured on 2026-11-05 on the lab with all 28 Argo CD apps Synced and Healthy. There is no metrics-server, so pod figures are container working sets from Prometheus (`container_memory_working_set_bytes`), read through the API server proxy. The plan's "12 GB" is Docker Desktop's limit, which the node sees as 11.9 GiB; at this precision the plan's GB and the measured GiB are compared directly.

| Component | Plan | Measured now | Notes |
| --- | --- | --- | --- |
| Kind, one node (system pods) | 0.9 GB | 1.94 GiB | `kube-apiserver` alone is 1.46 GiB: every operator adds CRDs and watches (Argo CD, CloudNativePG, Prometheus, RabbitMQ, Kyverno, cert-manager) |
| Argo CD | 0.6 GB | 0.80 GiB | application controller 0.6 GiB for 28 apps |
| Prometheus, Grafana, Alertmanager, node exporter | 1.5 GB | 1.48 GiB | includes the operator and kube-state-metrics |
| Loki and Tempo (single binary) | 0.8 GB | 0.25 GiB | with the OTel Collector; little traffic yet |
| Keycloak | 0.7 GB | 0.53 GiB | its database is counted under Postgres |
| Postgres x3 and operator, RabbitMQ x2, Garage x2 | 1.95 GB | 0.66 GiB | RabbitMQ is 0.13 GiB per environment; each Postgres under 0.1 GiB |
| Kyverno | 0.4 GB | 0.17 GiB | admission and background controllers |
| cert-manager and the Barman Cloud Plugin | 0.15 GB | 0.16 GiB | |
| Services x2 environments | 2.0 GB | 0.14 GiB | only the stub BFF so far: 48 MiB per replica, 1 in dev and 2 in prod |
| Ingress, Stripe forwarders, traffic generator | 0.4 GB | 0.07 GiB | Traefik and Mailpit; the forwarders and generator come later |
| **Pods, total** | **about 9.5 GB** | **6.16 GiB** | |

Over the last 24 hours of the same series: median 5.95 GiB, 95th percentile 7.25 GiB. The total was above 9 GiB for about 10 minutes, during a start, when old and new containers overlap. `docker stats` shows the node container at 7.1 of 11.9 GiB, which adds the kubelet, containerd and page cache to the pods. The mini reported 36% of its 16 GB free with the lab up.

What it means:

- **Well under the 11 GB line**, so dev services do not need to scale to zero.
- **The plan's split was wrong, its total was not.** The control plane and Argo CD use about twice the estimate, because of the number of CRDs and watched objects; the data stores and the log and trace stores use a third of it at today's load. Loki, Tempo and Postgres will grow with traffic and retention.
- **Projection for Sprint 2 onwards:** the remaining services (Listings on the JVM, Orders, Payments, Notifications, in two environments), the Stripe forwarders and the traffic generator add about 2 GiB if they match the plan, which puts pods near 8 GiB median and 9.5 GiB at the 95th percentile. Re-measure at the end of Sprint 2 with real traffic, and watch `kube-apiserver` as CRDs are added.

## Changes From the Spec

| Planned | Actual | Why |
| --- | --- | --- |
| ingress-nginx | Traefik (R18) | ingress-nginx was retired in March 2026: no more security fixes |
| MinIO | Garage (R19) | MinIO's community edition is archived |
| Stripe Express accounts through Accounts v1 | Accounts v2 with `dashboard: none` and Stripe-hosted onboarding (R17) | New sandboxes refuse v1 account creation, and Express needs the platform as losses collector, which this platform cannot be |
| Kyverno `ClusterPolicy` | `ValidatingPolicy` (R20) | The legacy `ClusterPolicy` type is removed in Kyverno 1.20 |
| Terraform state in the clone | `~/sv-terraform` on the mini, outside any clone | `make rebuild` and Jenkins must share one state |
| BFF `/healthz` checked through `https://<env>.sortedvtg.lan` | Checked in-cluster through the API server proxy | The BFF has no Ingress until its pages arrive in Sprint 2 |
| `kubectl top` for T032 | Prometheus working-set series | No metrics-server in the cluster; Prometheus also gives 24-hour history |

## What We Learned

- **Spike first, every time.** Each throwaway-cluster spike caught a real bug before it reached the lab: Garage's readiness deadlock, a duplicated RabbitMQ namespace, Argo CD's metrics label, the Kyverno rule that would have refused the PV controller's own updates.
- **Some mistakes cannot be fixed from Git.** Keycloak imports a realm once, and StatefulSets do not replace a pod that never became Ready. Both need checking before the lab sees the change.
- **Verify scripts rot as the lab moves.** Two checks broke silently between tickets (the state move and the missing Ingress). Running the script in every Jenkins build now catches that on the next commit.
- **Estimate the control plane by what it watches, not by node count.** One node, but many operators: the API server is the largest single pod.

## Follow-Ups

- [x] `make down` / `make up` back to healthy in under 10 minutes with history intact (Ticket 1.6, above).
- [x] An `infra-terraform` run that pauses for approval and applies (Ticket 1.7 acceptance; build #6, above).
- [ ] The cluster apply prints the Kind client and CA certificates as outputs in the Jenkins log. They are public certificates (the client key is marked sensitive and hidden), but marking those outputs sensitive too would keep the log clean.
- [ ] Re-measure memory at the end of Sprint 2 with the services and traffic generator running.
- [ ] Docker Desktop over SSH cannot pull a new Kind node image without the keychain (`spikes.md`, T008): pre-pull it in `bot`'s desktop session as part of any Kind upgrade.
- [ ] Switch `tfsec` to `trivy config`; tfsec is being folded into Trivy.
- [ ] From convergence, for later sprints: T110 (restore-mode layout, with T076), T113 (5-second browse check), T114 (Argo CD notifications, with T086).
