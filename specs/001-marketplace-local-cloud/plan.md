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
**Target Platform**: Kind on Docker Desktop on a Mac mini M4, linux/arm64 images, reached over SSH from the MacBook Air (Tailscale optional)
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
| Payments | Stripe Connect Express, destination charges with an application fee; Account Links for onboarding | Clarification 2026-10-29 |
| Webhooks into the lab | A `stripe listen --forward-to` Deployment in each namespace | The lab has no public ingress (Constitution VI) |
| Double-sell protection | Conditional update `available → reserved` in Listings, with a reservation row and 10-minute expiry sweeper | Single source of truth for item state (FR-009) |
| Idempotency | Unique constraint on the Stripe event ID; state transitions validated in Orders | FR-011 |
| Search | Postgres full-text search in Listings | Avoids a search engine on a 16 GB host |
| Events | RabbitMQ topic exchange `orders`; quorum queue per consumer; dead-letter queue after 5 attempts | FR-016, FR-017 |
| Environment generation | Argo CD ApplicationSet with a Git directory generator over `services/*/overlays/*` | FR-025; adding a folder adds an environment |
| Databases | CloudNativePG `Cluster` per namespace, scheduled backups and on-demand `Backup` resources to MinIO | Constitution VIII; declarative backups replace scripts; chosen over Crossplane (ADR-0005) |
| Backup durability | MinIO's volume is a Kind `extraMount` on the mini's disk, outside the cluster lifecycle | Backups survive the rebuild drill |
| Policy | Kyverno in the cluster (enforce) and `kyverno apply` in the GitOps repo's CI on every PR, same policy files | Constitution III; FR-027 |
| Service template | Copier template in `app/templates/service-fastapi` with OTel, health, metrics, Dockerfile, kustomize base | FR-026 |
| Environments | `sv-dev` and `sv-prod` namespaces; shared platform add-ons in their own namespaces | Clarification 2026-10-29 |
| Sessions | `make up` starts the Kind node containers and waits for Argo CD health; `make down` creates CloudNativePG `Backup` resources, waits for them, then stops the nodes. Data and telemetry live on persistent volumes | Clarification 2026-10-29; FR-024 |
| Images | GitHub Actions on `ubuntu-24.04-arm`, Trivy, push to GHCR, tag commit to GitOps repo | Constitution I; Intel Mac stays out of the build path |
| Infra pipeline | Jenkins controller on the Intel Mac, agent on the mini, plan → approval → apply | Constitution III; reuses the existing Jenkinsfile stages |

### Memory budget (estimate, to be measured in Sprint 1)

| Component | Estimate |
| --- | --- |
| Kind control plane and 2 workers (system pods) | 1.2 GB |
| Argo CD | 0.6 GB |
| Prometheus, Grafana, Alertmanager, node exporter | 1.5 GB |
| Loki and Tempo (single-binary mode) | 0.8 GB |
| Keycloak | 0.7 GB |
| Postgres x2 (CloudNativePG) and its operator, RabbitMQ x2, MinIO | 1.7 GB |
| Kyverno (admission and background controllers) | 0.4 GB |
| Services x2 environments (Listings JVM 0.4 GB, others 0.15 GB) | 2.0 GB |
| Ingress, Stripe forwarders, traffic generator | 0.4 GB |
| **Total** | **about 9.3 GB of 12 GB** |

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
| VI. Secure by default | Pass | Stripe test keys in Kubernetes Secrets created by Terraform from a local, git-ignored file; Trivy gate; non-root containers; Tailscale only |
| VIII. Declarative infrastructure | Pass | Terraform stops at the cluster and Argo CD; databases, buckets and backups are CloudNativePG and Kubernetes resources |
| VII. Modest app | Pass | No offers, shipping, messaging or ratings; Postgres search instead of a search engine |

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
├── platform/{ingress-nginx, kube-prometheus-stack, loki, tempo, otel-collector, keycloak, rabbitmq, postgres, minio, mailpit}/
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
