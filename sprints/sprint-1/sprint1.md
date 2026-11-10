Sorted Vintage — Sprint 1 Actionable Engineering Specification
Document Status: Draft for review
Target Release: Sprint 1, Foundation (Nov 2 – Nov 15, 2026)
Author: Platform Engineering
Source: specs/001-marketplace-local-cloud/tasks.md, Phases 1–2, T080 and T103–T106

1. Executive Summary & Sprint 1 Objective

Sprint 1 builds the platform every user story runs on. Terraform creates a single-node Kind cluster on the lab host and installs Argo CD. From then on, Argo CD installs everything else from `sorted-vintage-gitops`: ingress (Traefik), observability, Postgres with continuous backups, RabbitMQ, Garage, Mailpit, Keycloak and Kyverno. A Copier template produces services that meet the constitution from their first commit, and a stub BFF generated from it travels the full delivery path: GitHub Actions build, a tag commit to Git, Argo CD sync in dev, and a gated promotion to prod. Jenkins runs on the workstation, bound to loopback, with its build agent on the lab host, and SonarQube Cloud checks code quality on every pull request. The sprint ends with `make up` and `make down` for working sessions, and a measured memory budget.

Sprint Objective
One `make rebuild` on the lab host ends with every Argo CD Application `Synced` and `Healthy`, Kyverno rejecting non-compliant workloads, and the stub BFF answering `https://dev.sortedvtg.lan:8443/healthz` from the workstation through the SSH tunnel.

Decisions carried in (accepted 2026-10-29, see plan.md Complexity Tracking)
- Single-node Kind (research R1). The T008 spike confirms it survives stop and start before any Terraform is written.
- No Tailscale yet (research R2). Ingress binds to the lab host's loopback address; the workstation reaches it with `ssh -N -L 8443:127.0.0.1:443 lab`.
- Session-end backups write nothing to the cluster (research R14). WAL archiving runs continuously; `make down` only checks that it is current.
- The lab is two machines (research R15). The Jenkins controller runs on the workstation as its own standard account (not the workstation's everyday account), bound to `127.0.0.1:8080`, and builds only `main` of `sorted-vintage-infra`; the third machine is no longer used. Code quality uses SonarQube Cloud's free plan.
- The lab runs as the lab host's standard account `bot` (ADR-0008): Docker Desktop, Kind, the infra clone, `secrets.auto.tfvars` and the Jenkins agent. `bot` stays logged in at the lab host's screen during a session. The lab host's admin account only installs Homebrew packages and changes system settings. From the workstation, `ssh lab` is `bot` and `ssh lab-admin` is the admin.

2. Lab Topology After Sprint 1

   ┌───────────────────────────────────┐  ssh -N -L 8443:127.0.0.1:443   ┌──────────────────────────────────────────────────────────┐
   │  Workstation (16 GB)              ├────────────────────────────────►│  Lab host (16 GB), account bot, Docker Desktop (12 GB)   │
   │  Browser → *.sortedvtg.lan:8443   │                                 │  Kind node "sorted-vintage" (80/443 on 127.0.0.1 only)   │
   │  /etc/hosts → 127.0.0.1           │  ssh (key sv_jenkins_agent)     │   argocd · traefik · cert-manager · kyverno              │
   │  Jenkins (own standard account)   ├────────────────────────────────►│   prometheus · grafana · loki · tempo · otel-collector   │
   │    127.0.0.1:8080, no executors   │  starts the agent               │   keycloak (realms sv-dev, sv-prod)                      │
   └──────┬──────────────────▲─────────┘                                 │   sv-dev / sv-prod: postgres · rabbitmq · garage ·        │
          │ git push         │ Jenkins polls main every 5 min            │                     mailpit · bff (stub)                 │
          │                  │                                           │  Jenkins agent (label lab): terraform, kind, docker      │
          │                  │                                           │  ~/sv-data (extraMount): Garage photos and backups      │
          │                  │                                           └───────────────▲──────────────────────────────────────────┘
          │                  │                                                           │ Argo CD pulls
   ┌──────▼──────────────────┴───────────────────────────────────────────────────────────┴──────┐
   │  GitHub: infra · app (Actions → Trivy → SonarQube Cloud → GHCR, tag commit)                │
   │          gitops (policy CI, prod-gate)                                                     │
   └────────────────────────────────────────────────────────────────────────────────────────────┘

3. Actionable Engineering Tickets & Implementation Specs

Ticket 1.1 — Confirm the Research Decisions Before Building on Them (T007, T008, T009)
Owner: Platform Engineer
Story: As the platform owner, I want the two riskiest assumptions tested on the real hardware first, so that a week of Terraform is not built on a cluster that cannot restart.

Implementation Requirements:
- T008 Kind restart spike on the lab host: create a one-node cluster, run a pod with a PVC that writes a file, `docker stop` and `docker start` the node container, and confirm the API server, the pod and the file return. Record the commands and result in `sprints/sprint-1/spikes.md`. If it fails, stop and revisit research R1 before Ticket 1.2.
- T009 Stripe spike: create sandboxes `sorted-vintage-dev` and `sorted-vintage-prod` with Connect enabled; run `stripe listen --forward-to … --forward-connect-to …` against a local echo server; trigger `payment_intent.succeeded` and `account.updated`; record whether both streams use the same signing secret. Done: one secret per sandbox, and connected accounts move to Accounts v2 (research R17, `spikes.md`).
- T007 Pre-commit hooks: `terraform_fmt` and `terraform_validate` in infra; `ruff`, `ruff-format` and `hadolint` in app; `check-jsonschema` for Kubernetes YAML in gitops. Then `pre-commit autoupdate`, one pull request per repository. This also closes the Sprint 0 follow-up and is the first real test of the branch rules.
- Add `mkcert`, `stripe/stripe-cli/stripe`, `kyverno` and `tfsec` to `scripts/Brewfile` and install them on the lab host as the admin (`ssh lab-admin`), since Homebrew belongs to that account. On the workstation, install only what it needs; its Terraform comes from homebrew-core, not the HashiCorp tap (Sprint 0 retro).
- Clone `sorted-vintage-infra` on the lab host as `bot` (`ssh lab`) into `~/Sorted-Vintage/src/`, and run the spikes there as `bot`.

Acceptance Criteria Verification:
- `spikes.md` records a passing Kind restart and the Stripe signing-secret answer.
- Three merged pull requests with the new hooks and green checks.

Ticket 1.2 — Cluster and Argo CD From One Terraform Apply (T010, T011, T012)
Owner: Platform / SRE Engineer
Story: As the platform owner, I want Terraform to create exactly what must exist before Kubernetes, so that everything after it is declared in Git and rebuilt by Argo CD (Principles II and VIII).

Implementation Requirements:
- T010 `terraform/modules/kind-cluster/` and `terraform/cluster/main.tf` (provider `tehcyx/kind`): cluster `sorted-vintage`, one control-plane node that runs workloads, `extraPortMappings` for 80 and 443 with `listenAddress` from variable `ingress_listen_address` (default `"127.0.0.1"`; set to the Tailscale IP once it exists), and an `extraMounts` entry from variable `lab_data_dir` (default `~/sv-data`) to `/var/lab-data`.
- T011 `terraform/modules/argocd-bootstrap/` and `terraform/bootstrap/main.tf`: Argo CD by Helm in `argocd`, plus one `Application` for `gitops/bootstrap/root-app.yaml`.
- T012 `terraform/modules/secrets/`: Kubernetes Secrets in `sv-dev` and `sv-prod` from the git-ignored `terraform/bootstrap/secrets.auto.tfvars`, holding each environment's Stripe keys and signing secret (from its own sandbox), database passwords, and the mkcert `*.sortedvtg.lan` certificate as a TLS Secret in `traefik`. Commit only `secrets.auto.tfvars.example`, with placeholders.

Acceptance Criteria Verification:
- `terraform apply` for `cluster` then `bootstrap` succeeds on the lab host, and a second `terraform plan` for each shows no changes.
- `docker port sorted-vintage-control-plane 443` shows `127.0.0.1:443` only.
- `git ls-files` shows no `*.tfvars` other than the example.

Ticket 1.3 — Platform Add-Ons Delivered by Argo CD (T016–T025)
Owner: Platform Engineer
Story: As the platform owner, I want every shared component installed from the GitOps repository, so that a rebuild reproduces it exactly and drift is visible.

Implementation Requirements:
- T016 `bootstrap/root-app.yaml` (app-of-apps over `platform/`) and `bootstrap/services-appset.yaml`: a Git directory generator over `services/*/overlays/*`, app name `<service>-<overlay>`, namespace `sv-<overlay>` (FR-025).
- T017 cert-manager, required by the Barman Cloud Plugin.
- T018 Traefik (research R18; ingress-nginx is retired) with the T012 certificate as default, hosts `dev`, `prod`, `grafana`, `argocd` and `mail` under `sortedvtg.lan`.
- T019 kube-prometheus-stack and T020 Loki, Tempo and the OpenTelemetry Collector, all with persistent volumes so telemetry survives sessions (FR-024).
- T021 CloudNativePG operator and Barman Cloud Plugin; per namespace a `Cluster` with databases `listings`, `orders`, `payments`, `notifications`; an `ObjectStore` on that namespace's MinIO bucket `backups`; continuous WAL archiving with `archive_timeout: 60s`; a daily `ScheduledBackup` with `immediate: true`. Record in `spikes.md` which status field reports the last archived WAL time (needed by Ticket 1.6).
- T022 Garage per namespace on `/var/lab-data/garage-<env>` (research R19; MinIO's community edition is archived), with buckets `photos` and `backups` and S3 keys imported from Terraform-created Secrets; spike that CloudNativePG backup and restore work against it.
- T023 RabbitMQ Cluster Operator and Messaging Topology Operator, one `RabbitmqCluster` per namespace.
- T024 Mailpit per namespace.
- T025 Keycloak with realms `sv-dev` and `sv-prod` from realm JSON: registration with email verification over Mailpit, a `display_name` attribute issued as a token claim, the confidential `bff` client (code flow with PKCE), and client-credentials clients `orders`, `payments`, `listings`, each with an audience mapper.

Acceptance Criteria Verification:
- Every Argo CD Application is `Synced` and `Healthy`.
- Each CloudNativePG `Cluster` reports continuous archiving as working, and the first base backup exists in Garage.
- Deleting a platform Deployment by hand is reverted by Argo CD (drift check; do this once and record it).

Ticket 1.4 — Policy at Admission and in CI (T026)
Owner: Security / Platform Engineer
Story: As the platform owner, I want the same policies to stop a bad manifest in the pull request and again at the cluster, so that neither layer is trusted alone (Principle III, FR-027).

Implementation Requirements:
- Kyverno from `platform/kyverno/` with enforce-mode policies in `gitops/policies/`: non-root containers, CPU and memory requests and limits required, images only from `ghcr.io/rclaye/`.
- The GitOps `checks` workflow runs `kyverno apply gitops/policies/ --resource <changed manifests>` on every pull request.
- `gitops/tests/policy/bad/` holds one failing manifest per rule; `gitops/tests/policy/good/` holds one that passes.
- Platform components that cannot meet a rule (for example images from upstream registries) are excluded by namespace in the policy, never by turning a rule to audit mode. List every exclusion in the policy file with its reason.

Acceptance Criteria Verification:
- `kubectl apply --dry-run=server` rejects every file in `tests/policy/bad/` and accepts `tests/policy/good/`.
- A pull request that adds a bad manifest under a service overlay fails its policy check.

Ticket 1.5 — Service Template and the Delivery Path (T027–T030, T080)
Owner: Platform Engineer
Story: As the platform owner, I want a service template and one stub service that goes from commit to dev to prod without anyone touching the cluster, so that every later service follows the same path (Principles I, III and V).

Implementation Requirements:
- T027 Copier template `app/templates/service-fastapi/`: `/healthz` and `/metrics`, OTel with OTLP export, JSON logs with trace IDs, JWT validation (401 without a valid token), the common error body, a non-root multi-stage `Dockerfile`, a pytest skeleton, and a kustomize `base` with `overlays/{dev,prod}` that pass Ticket 1.4's policies. The rules are listed in `specs/001-marketplace-local-cloud/contracts/README.md`.
- T028 Generate `app/services/bff/` from it as a stub.
- T029 `app/.github/workflows/build.yml`: lint, test, `linux/arm64` build on `ubuntu-24.04-arm`, Trivy (fail on critical), push to `ghcr.io/rclaye/sv-<service>:<git-sha>`, then commit the tag to the dev overlay with a GitOps deploy key. No cluster credentials anywhere in GitHub.
- T030 `gitops/services/bff/{base,overlays/dev,overlays/prod}` and `gitops/.github/workflows/promote.yml`, which opens a pull request copying a service's dev tag into its prod overlay.
- T080 The prod gate from ADR-0002: the GitHub Environment `prod` on the GitOps repo with you as required reviewer, created by `scripts/protect-prod.sh`; `gitops/.github/workflows/prod-gate.yml`, whose `prod-gate` job passes at once when no prod overlay changed and otherwise waits in environment `prod` for approval; `prod-gate` added to the GitOps repo's required checks. Pull request approvals stay at zero.

Acceptance Criteria Verification:
- A merged change to the stub BFF is running in `sv-dev` with no manual step.
- The promotion pull request cannot merge until the `prod` environment approval is given; after merge, `sv-prod` runs the same tag.
- `git revert` of the promotion commit returns prod to the previous tag.

Ticket 1.6 — Working Sessions (T013, T015)
Owner: Platform / SRE Engineer
Story: As the platform owner, I want one command to start a session and one to end it, so that the lab can be off between sessions without losing data or history (FR-024).

Implementation Requirements:
- T013 `Makefile` targets:
    - `up`: refuse to start unless it runs as `bot`, Docker answers and Ollama is not running; then start the Kind node container, then wait (up to 10 minutes) until every Argo CD Application is `Synced` and `Healthy`.
    - `down`: read-only. Wait until each CloudNativePG `Cluster` reports continuous archiving as working and its last archived WAL is no older than 120 seconds, wait 60 more seconds, then stop the node container. It creates nothing in the cluster (research R14).
    - `rebuild`: `terraform apply` for `cluster` then `bootstrap`, then wait for health.
    - `destroy`: `terraform destroy` for `bootstrap` then `cluster`. The Garage data on `~/sv-data` is kept.
- T015 `docs/runbooks/lab-session.md`: logging in as `bot` at the lab host's screen, the SSH tunnel, the `/etc/hosts` entries on the workstation (`dev`, `prod`, `grafana`, `argocd`, `mail`, `auth` under `sortedvtg.lan` → `127.0.0.1`), trusting the mkcert root CA, and `make up` / `make down`. Link it from `docs/runbooks/remote-access.md`.

Acceptance Criteria Verification:
- `make down` then `make up` returns every app to `Healthy` in under 10 minutes, and the Grafana history from before the stop is still there.
- `make down` makes no change to cluster state: after one run and `make up`, `kubectl get backups.postgresql.cnpg.io -A` lists only scheduled backups, and Argo CD shows no Application out of sync.

Ticket 1.7 — Jenkins on the workstation, and SonarQube Cloud (T104, T103, T014, T105, T106)
Owner: Platform / Security Engineer
Story: As the platform owner, I want to see the infrastructure pipeline and code-quality results in a browser without a third machine or any port open on my local network, so that CI is visible and the lab stays simple and closed (Principles III and VI).

Implementation Requirements:
- T104 Jenkins on the workstation, following `docs/runbooks/jenkins.md`:
    - On the workstation, from your everyday account, first close your home folder to other accounts (`chmod 700 ~`, and `chmod 600` on any credential file that is group- or world-readable).
    - Then run `scripts/jenkins/air-setup.sh` from that same everyday account; it asks for your password for the steps that act as the workstation's Jenkins account. It refuses to continue if that account is an admin. It installs `jenkins-lts`, and a LaunchDaemon that runs Jenkins as the workstation's Jenkins account, bound to `127.0.0.1:8080`, not started at boot. It creates the agent key `/Users/<jenkins-account>/.ssh/sv_jenkins_agent` (owner-only), and copies the lab host's host key from your verified `known_hosts`.
    - From the workstation, run the command the script prints. It runs `scripts/jenkins/authorize-agent-key.sh` on the lab host as `bot` through `ssh lab`. The key is `restrict`ed: it can run the agent but gets no forwarding and no pty.
    - Add `openjdk@21` to `scripts/Brewfile` for the lab host's agent.
- T103 Jenkins as code: `jenkins/plugins.txt` and `jenkins/casc.yaml` define the `mini-agent-ssh` credential (read from the key file, never committed), the `lab-host` agent (label `lab`, launched over SSH as the lab host's `bot`, so no agent port is opened), zero executors on the controller, and the `infra-terraform` pipeline job polling the `main` branch of `sorted-vintage-infra` every 5 minutes (GitHub cannot reach Jenkins). It is a single-branch job: no multibranch project, and no pull request or fork discovery.
- T014 `jenkins/Jenkinsfile` on agent `lab`: fmt, validate, tfsec, plan, manual approval, apply; destroy behind a second approval.
- T105 SonarQube Cloud free plan: organization `rclaye` bound to GitHub, the SonarQube Cloud GitHub App on `sorted-vintage-app`, automatic analysis off, project `rclaye_sv-bff`, `sonar-project.properties` in the BFF and the template, and a `sonar` step in `build.yml` after tests. You create `SONAR_TOKEN` in SonarQube Cloud and add it as a repository secret yourself. If the scan action does not run on `ubuntu-24.04-arm`, run only the scan job on `ubuntu-24.04`.
- T106 ADR-0008 (Jenkins on the workstation; SonarQube Cloud instead of self-hosted; the lab drops to two machines; Principle II reads "one command, `make rebuild`") and a MINOR amendment to the constitution (1.1.0 → 1.2.0). Done before T104 and T103.

Acceptance Criteria Verification:
- On the workstation, `sudo lsof -nP -iTCP:8080 -sTCP:LISTEN` shows `127.0.0.1:8080` only, owned by the workstation's Jenkins account, and `http://localhost:8080` shows Jenkins.
- The workstation's everyday account cannot read `/Users/<jenkins-account>/.ssh/sv_jenkins_agent`, and the workstation's Jenkins account is not in the `admin` group.
- Jenkins has exactly one job, `infra-terraform`, and it builds `main` only.
- The `lab-host` agent is online in Jenkins and runs as the lab host's `bot`, which is not in the `admin` group, and an `infra-terraform` run shows plan, a paused approval, and apply on it.
- A pull request to `sorted-vintage-app` shows the SonarQube Cloud quality gate.

Ticket 1.8 — Verify and Measure (T031, T032)
Owner: Platform Engineer
Story: As the platform owner, I want the sprint's claims checked by a script and the memory budget measured, so that Sprint 2 starts from facts rather than estimates.

Implementation Requirements:
- T031 `sprints/sprint-1/verify_sprint1.sh` (in this folder), run from the workstation.
- T032 Measure real memory use with `docker stats` and `kubectl top` against the plan's estimate (about 9.5 GB of 12 GB) and record it in `sprints/sprint-1/sprint1_retro.md`. Above 11 GB, scale dev services to zero when idle before cutting anything else.

Acceptance Criteria Verification:
- `verify_sprint1.sh` passes.
- The retro records measured memory by component next to the plan's estimate.

4. Sprint Verification

Run `sprints/sprint-1/verify_sprint1.sh` from the workstation with the lab up. It runs on the workstation and over SSH on the lab host and makes no change to the cluster. It checks the lab host's toolchain, the single node and its loopback-only ingress binding, Jenkins on the workstation bound to loopback, the Jenkins agent key reaching Java on the lab host, the SonarQube Cloud check on the app repository, Argo CD health, the BFF in both environments, policy rejection with server-side dry runs, WAL archiving, an empty Terraform plan, the `prod` environment's required reviewer, and that no tfvars file is tracked. It exits non-zero on the first failure.

5. Out of Scope for Sprint 1

Listings, Orders, Payments and Notifications code; SonarQube Cloud projects for services other than the BFF (each is added with its service); the Stripe forwarder Deployment (Sprint 2, T049); the traffic generator; dashboards beyond the stack's defaults; Tailscale; the rebuild drill with restore (Sprint 3).
