# Implementation Plan: Sorted Vintage Marketplace on the Local Cloud

**Branch**: `001-marketplace-local-cloud` | **Date**: 2026-10-29 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-marketplace-local-cloud/spec.md`

## Summary

Build the version 1 marketplace (accounts, listings with photos, buy-now checkout with Stripe Connect Express in test mode, email notifications) as five services, and the local platform that runs it: a Kind cluster on the Mac mini built by Terraform, delivered by Argo CD from a GitOps repository, with images built by GitHub Actions on arm64 runners. Every service ships with metrics, logs and traces from day one, and a traffic generator keeps the platform busy so later projects have baselines to learn from.

## Technical Context

**Language/Version**: Python 3.12 (FastAPI services, BFF, traffic generator); Java 21 (Spring Boot 3 Listings service); HCL (Terraform 1.9+)
**Primary Dependencies**: FastAPI, SQLAlchemy 2, Jinja2 + HTMX (BFF pages), Spring Boot 3 (Web, Data JPA), Stripe SDK, OpenTelemetry SDKs and auto-instrumentation, Keycloak (OIDC), RabbitMQ client (aio-pika), Locust (traffic)
**Storage**: PostgreSQL via the CloudNativePG operator, one cluster per environment with a database per service, backups to MinIO; MinIO for photos; RabbitMQ for events
**Testing**: pytest + httpx, JUnit 5 + Testcontainers, contract tests on service APIs, k6 or Locust for SC-002 and SC-003, `verify_sprintN.sh` per sprint
**Target Platform**: single-node Kind on Docker Desktop on a Mac mini M4, linux/arm64 images; ingress bound to the mini's loopback and reached over an SSH tunnel from the MacBook Air until Tailscale is installed (research R1, R2)
**Project Type**: Web application, multi-service, across three repositories
**Performance Goals**: p95 checkout under 2 s at the baseline traffic rate (SC-002); zero double-sales across 1,000 concurrent attempts (SC-003)
**Constraints**: the lab runs in working sessions, so state must survive stop and start; at most 12 GB for all containers on the mini; $0 recurring cost; no inbound internet access to the lab (Stripe webhooks arrive through the Stripe CLI forwarder)
**Scale/Scope**: about 50 synthetic users, 500 listings, a few requests per second, 2 environments, 5 services

### Key design decisions

| Decision | Choice | Why |
| --- | --- | --- |
| Service split | BFF (pages + session), Listings, Orders, Payments, Notifications | Gives a synchronous checkout chain and an asynchronous event path (Constitution VII) |
| Frontend | Server-rendered Jinja + HTMX in the BFF | Clarification 2026-10-29; no separate frontend build |
| Auth | Keycloak, one instance, one realm per environment; BFF does the OIDC code flow and holds the session; services validate JWTs | One identity system, separate users per environment, and real token-expiry failures |
| Payments | Stripe Connect Express, destination charges with an application fee; Account Links for onboarding; PaymentIntents with the Payment Element | Clarification 2026-10-29; the traffic generator can confirm PaymentIntents without a browser (research R6) |
| Stripe accounts | One test-mode sandbox per environment | Each `stripe listen` receives every event on its account, so a shared account would cross dev and prod (research R3) |
| Webhooks into the lab | A `stripe listen --forward-to … --forward-connect-to …` Deployment in each namespace | The lab has no public ingress (Constitution VI); research R4 |
| Missed events | Payments reconciles pending orders and onboarding status against Stripe at startup and every 5 minutes | Events sent while the lab is off are never forwarded (research R5) |
| Double-sell protection | Conditional update `available → reserved` in Listings, with a reservation row and 10-minute expiry sweeper | Single source of truth for item state (FR-009) |
| Idempotency | Payments stores each Stripe event once (inbox, unique on event ID) and applies it with retries; Orders validates state transitions and publishes through an outbox | FR-011; no lost events or dual writes when a service restarts mid-checkout (research R8) |
| Search | Postgres full-text search in Listings | Avoids a search engine on a 16 GB host |
| Events | RabbitMQ topic exchange `orders`; quorum queue per consumer; dead-letter queue after 5 attempts | FR-016, FR-017 |
| Environment generation | Argo CD ApplicationSet with a Git directory generator over `services/*/overlays/*` | FR-025; adding a folder adds an environment |
| Databases | CloudNativePG `Cluster` per namespace; scheduled and on-demand backups to MinIO through the Barman Cloud Plugin (needs cert-manager) | Constitution VIII; declarative backups replace scripts; the in-tree backup support is deprecated (research R10); chosen over Crossplane (ADR-0005, not yet written) |
| Backup durability | MinIO's volume is a Kind `extraMount` on the mini's disk, outside the cluster lifecycle | Backups survive the rebuild drill |
| Policy | Kyverno in the cluster (enforce) and `kyverno apply` in the GitOps repo's CI on every PR, same policy files | Constitution III; FR-027 |
| Service template | Copier template in `app/templates/service-fastapi` with OTel, health, metrics, Dockerfile, kustomize base | FR-026 |
| Environments | `sv-dev` and `sv-prod` namespaces; shared platform add-ons in their own namespaces | Clarification 2026-10-29 |
| Sessions | `make up` starts the Kind node container and waits for Argo CD health; `make down` checks, read-only, that each database's WAL archive is current, then stops the node. Continuous WAL archiving (`archive_timeout` 60 s) and a daily `ScheduledBackup` are declared in Git, so nothing is written to the cluster at session end (research R14). Data and telemetry live on persistent volumes | Clarification 2026-10-29; FR-024 |
| Images | GitHub Actions on `ubuntu-24.04-arm`, Trivy, push to GHCR, tag commit to GitOps repo | Constitution I; no local machine in the image build path |
| Infra pipeline | Jenkins controller on the MacBook Air, as its own standard account, bound to loopback, building `main` only; agent on the mini launched over SSH; jobs poll Git; plan → approval → apply | Constitution III and VI; no port open on the home network, and no third machine (research R15) |
| Code quality | SonarQube Cloud free plan, CI-based analysis per service from GitHub Actions, quality gate on each pull request | Free for public repositories; no server to run (research R15) |

### Memory budget (estimate, to be measured in Sprint 1)

| Component | Estimate |
| --- | --- |
| Kind, one node (system pods) | 0.9 GB |
| Argo CD | 0.6 GB |
| Prometheus, Grafana, Alertmanager, node exporter | 1.5 GB |
| Loki and Tempo (single-binary mode) | 0.8 GB |
| Keycloak | 0.7 GB |
| Postgres x2 (CloudNativePG) and its operator, RabbitMQ x2, MinIO | 1.7 GB |
| Kyverno (admission and background controllers) | 0.4 GB |
| cert-manager and the Barman Cloud Plugin | 0.15 GB |
| Services x2 environments (Listings JVM 0.4 GB, others 0.15 GB) | 2.0 GB |
| Ingress, Stripe forwarders, traffic generator | 0.4 GB |
| **Total** | **about 9.2 GB of 12 GB** |

If the measured total exceeds 11 GB, dev services scale to zero when not in use before anything else is cut.

## Constitution Check

*GATE: must pass before research; re-checked after design.*

| Principle | Status | How the plan meets it |
| --- | --- | --- |
| I. Git is the only path | Pass | GitHub Actions and Jenkins have no kubeconfig for workloads; Argo CD syncs from `sorted-vintage-gitops`; prod via PR |
| II. Rebuildable from code | Pass | `infra/terraform/cluster` and `infra/terraform/bootstrap`; seed job runs as an Argo CD PostSync hook; rebuild drill in Sprint 3 |
| III. Gate before change | Pass | Jenkins approval before apply; prod overlays change only by PR; Kyverno policies run in CI and at admission |
| IV. Ground truth | N/A | No AI claims in this feature; change events and traffic patterns are prepared for Project 2 |
| V. Observable by default | Pass | OTel SDK in every service, trace context propagated through RabbitMQ message headers, JSON logs with trace IDs |
| VI. Secure by default | Pass with deviation | Stripe test keys in Kubernetes Secrets created by Terraform from a local, git-ignored file; Trivy gate; non-root containers. Jenkins listens on the Air's loopback only and runs as a dedicated standard account, not the everyday one (research R15). Tailscale is deferred (Sprint 0 retro), so the lab is reached by key-only SSH on the home network with ingress bound to loopback; see Complexity Tracking |
| VIII. Declarative infrastructure | Pass | Terraform stops at the cluster and Argo CD; databases, buckets and backups are CloudNativePG and Kubernetes resources |
| VII. Modest app | Pass | No offers, shipping, messaging or ratings; Postgres search instead of a search engine |

### Post-design re-check (after research and Phase 1)

Re-run on 2026-10-29 against [research.md](./research.md), [data-model.md](./data-model.md) and [contracts/](./contracts/):

- **I, III, VIII**: still pass. Reconciliation, inbox and outbox change only application data; change events write only to Grafana and Loki; backups are continuous WAL archiving and `ScheduledBackup` resources declared in Git and reconciled by CloudNativePG; `make down` only reads their status (research R14).
- **II**: still passes, and gets simpler: a single Kind node survives stop and start without manual repair (research R1).
- **V**: passes, with one obligation the design adds: the outbox stores `traceparent` so the queued step stays in the checkout trace (research R9).
- **VI**: deviation unchanged (Tailscale deferred). Every service route needs a JWT except the two Stripe webhook routes, which need a Stripe signature (contracts/README.md).
- **VII**: passes. Nothing added beyond v1 scope; cert-manager is the only new platform component, and the backup plugin requires it.

**Jenkins exception:** the Jenkins agent on the mini runs `terraform apply`, which creates the cluster and installs Argo CD. That is infrastructure creation, not workload deployment, and it is the only cluster-scoped write outside Argo CD. Recorded in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-marketplace-local-cloud/
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0: Stripe Connect local webhooks, OTel over RabbitMQ, Kind on Docker Desktop networking
├── data-model.md        # Phase 1: entities, states and transitions
├── quickstart.md        # Phase 1: empty machine to first purchase
├── contracts/           # Phase 1: OpenAPI per service, AsyncAPI for the orders exchange
└── tasks.md             # Phase 2: /speckit.tasks output
```

### Source Code (three repositories)

```text
sorted-vintage-infra/
├── terraform/
│   ├── modules/{kind-cluster, argocd-bootstrap, secrets}/
│   ├── cluster/            # replaceable: Kind nodes, port mappings
│   └── bootstrap/          # Argo CD, root app, secrets from local file
├── jenkins/Jenkinsfile     # plan → approval → apply / destroy, rebuild drill
├── docs/{adr/, runbooks/}
├── .specify/ and specs/    # this Spec Kit workspace
└── sprints/sprint-N/

sorted-vintage-app/
├── services/
│   ├── bff/                # FastAPI + Jinja + HTMX, OIDC session
│   ├── listings/           # Spring Boot, MinIO, Postgres FTS, reservations
│   ├── orders/             # FastAPI, checkout orchestration
│   ├── payments/           # FastAPI, Stripe Connect, webhooks, ledger
│   └── notifications/      # FastAPI worker, RabbitMQ consumer, SMTP to Mailpit
├── templates/service-fastapi/   # Copier template for new services
├── tools/{traffic, seed}/
├── docker-compose.yml      # local development on the MacBook Air
└── .github/workflows/      # build, test, scan, publish, bump tag

sorted-vintage-gitops/
├── bootstrap/root-app.yaml
├── platform/{cert-manager, ingress-nginx, kube-prometheus-stack, loki, tempo, otel-collector, keycloak, rabbitmq, postgres, minio, mailpit}/
└── services/<name>/{base, overlays/dev, overlays/prod}/
```

**Structure Decision**: three repositories so that CI, desired state and infrastructure have separate owners and permissions (Constitution I and III).

## Complexity Tracking

| Deviation | Why needed | Simpler alternative rejected because |
| --- | --- | --- |
| Jenkins agent writes to the cluster once, at creation | Something has to create the cluster and install Argo CD | Hand-installing Argo CD violates Principle II |
| Shared Keycloak for both environments | Saves about 0.7 GB | Separate realms keep users and data independent, which satisfies FR-019 |
| CloudNativePG instead of Crossplane for databases | Declarative Postgres with backups, about 0.1 GB | Crossplane adds a composition layer with no cloud API to call locally; it fits the Project 6 self-service layer instead |
| Stripe CLI forwarder in the cluster | Webhooks cannot reach a lab with no public ingress | A public tunnel would open the lab to the internet (Principle VI) |
| Lab reached over SSH on the home network instead of Tailscale (Principle VI); accepted 2026-10-29 | Tailscale was deferred in Sprint 0 after the client misbehaved | Waiting for Tailscale blocks Sprint 1. Exposure is limited by binding ingress to loopback and allowing key-only SSH; ends when the Sprint 0 Tailscale follow-up is done, or the constitution is amended by ADR |
| Single Kind node instead of one control plane and two workers; accepted 2026-10-29 | Multi-node Kind clusters can fail to restart when Docker reassigns node IPs, which breaks FR-024 | Repairing node IPs by script is a manual step (Principle II); revisit when a Failure Lab scenario needs node failure |
