# Tasks: Sorted Vintage Marketplace on the Local Cloud

**Input**: Design documents from `specs/001-marketplace-local-cloud/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Format**: `- [ ] T### [P] [US#] Description with path`
- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[US#]**: the user story the task serves; setup, foundational and polish tasks carry none
- Paths are prefixed by repository: `infra/`, `app/`, `gitops/`

**Sprint mapping**: Phases 1–2 = Sprint 1 · Phases 3–4 = Sprint 2 · Phases 5–8 = Sprint 3 · Phase 9 = Gate 1 release

---

## Phase 1: Setup (Sprint 0 / start of Sprint 1)

- [ ] T001 Create repositories `sorted-vintage-infra`, `sorted-vintage-app`, `sorted-vintage-gitops` with README, LICENSE and branch protection on `main`
- [ ] T002 [P] Add `.gitignore` (from the Clixx Terraform repo) and `.pre-commit-config.yaml` with gitleaks, terraform fmt, ruff and hadolint in all three repos
- [ ] T003 [P] Copy this Spec Kit workspace into `infra/.specify/` and `infra/specs/`
- [ ] T004 [P] Write `infra/docs/adr/0001-local-kind-instead-of-eks.md` and `0002-git-is-the-only-path-to-the-cluster.md`
- [ ] T005 Write `specs/001-marketplace-local-cloud/research.md`: Stripe Connect test-mode onboarding and local webhook forwarding, OTel context over RabbitMQ headers, Kind port mapping on OrbStack

## Phase 2: Foundational (Sprint 1, blocks every story)

**Checkpoint**: one `terraform apply` on the mini ends with Argo CD healthy and a stub BFF answering at `dev.sortedvtg.lan/healthz`.

- [ ] T006 Write `infra/terraform/modules/kind-cluster/` (1 control plane, 2 workers, ports 80/443 mapped) and `infra/terraform/cluster/main.tf`
- [ ] T007 Write `infra/terraform/modules/argocd-bootstrap/` (Helm release, root app pointing at `gitops/bootstrap/root-app.yaml`) and `infra/terraform/bootstrap/main.tf`
- [ ] T008 Write `infra/terraform/modules/secrets/` creating Kubernetes Secrets (Stripe test keys, database passwords) from a git-ignored `secrets.auto.tfvars`
- [ ] T009 Write `gitops/bootstrap/root-app.yaml`, an app-of-apps for `platform/`, and an ApplicationSet with a Git directory generator over `services/*/overlays/*` (FR-025)
- [ ] T010 [P] Add `gitops/platform/ingress-nginx/` and mkcert-issued TLS for `*.sortedvtg.lan`
- [ ] T011 [P] Add `gitops/platform/kube-prometheus-stack/` with retention sized to the memory budget
- [ ] T012 [P] Add `gitops/platform/loki/`, `gitops/platform/tempo/` and `gitops/platform/otel-collector/`
- [ ] T013 [P] Add the CloudNativePG operator and a `Cluster` per namespace in `gitops/platform/postgres/`; add `rabbitmq/`, `minio/` (volume on a Kind extraMount) and `mailpit/` per namespace `sv-dev` and `sv-prod`
- [ ] T014 [P] Add `gitops/platform/keycloak/` with realms `sv-dev` and `sv-prod`
- [ ] T015 Create stub `app/services/bff/` (FastAPI, `/healthz`, `/metrics`, OTel, JSON logs) and multi-stage `Dockerfile` running as non-root
- [ ] T016 Write `app/.github/workflows/build.yml`: lint, test, Trivy (fail on critical), build on `ubuntu-24.04-arm`, push to GHCR, commit new tag to `gitops/services/bff/overlays/dev`
- [ ] T017 Write `gitops/services/bff/{base, overlays/dev, overlays/prod}` (picked up by the ApplicationSet) and a promotion workflow that opens a PR from dev tag to prod tag
- [ ] T018 Write `infra/jenkins/Jenkinsfile` (fmt, validate, tfsec, plan, approval, apply; destroy behind a second approval) and connect the mini as an agent
- [ ] T019 Write `infra/sprints/sprint-1/verify_sprint1.sh`: Argo CD apps synced and healthy, BFF `/healthz` 200 in both namespaces, `terraform plan` shows no changes
- [ ] T064 `make up` and `make down` in `infra/Makefile`: start the Kind node containers and wait for health; back up, then stop (FR-024)
- [ ] T020 Measure real memory use against the plan's budget and record it in `infra/sprints/sprint-1/sprint1_retro.md`

## Phase 3: User Story 1 - Seller signs up and lists an item (Sprint 2, P1) 🎯 MVP part 1

**Independent Test**: a new account completes test-mode payout onboarding, publishes a listing with two photos, and a signed-out visitor finds it by brand.

- [ ] T021 [P] [US1] Write `specs/001-marketplace-local-cloud/data-model.md` and `contracts/listings.openapi.yaml`
- [ ] T022 [P] [US1] Contract tests for Listings in `app/services/listings/src/test/.../ListingsContractTest.java`
- [ ] T023 [US1] BFF OIDC sign-up, sign-in and sign-out against Keycloak, session cookie, in `app/services/bff/app/auth.py`
- [ ] T024 [US1] Listings service: entities, Flyway migrations, CRUD, status field; edits and deletes refused while reserved; in `app/services/listings/`
- [ ] T025 [US1] Photo upload to MinIO with type and 10 MB checks (FR-005) in `app/services/listings/.../PhotoService.java`
- [ ] T026 [US1] Postgres full-text search and filters (FR-007) in `app/services/listings/.../SearchRepository.java`
- [ ] T027 [US1] Payout onboarding gate: Payments creates Connect Express accounts and Account Links; Listings refuses publish until onboarding is complete (FR-014), in `app/services/payments/app/connect.py`
- [ ] T028 [US1] BFF pages: browse, search, listing detail, sell form, seller profile (Jinja + HTMX) in `app/services/bff/app/templates/`
- [ ] T029 [US1] GitOps manifests for Listings and Payments in `gitops/services/{listings, payments}/`
- [ ] T030 [US1] Seed job (demo sellers, listings, photos) as an Argo CD PostSync hook in `app/tools/seed/` and `gitops/services/seed/`

## Phase 4: User Story 2 - Buyer purchases and seller is notified (Sprint 2–3, P1) 🎯 MVP part 2

**Independent Test**: buy one listing with a test card; order paid, listing sold, seller email in Mailpit.

- [ ] T031 [P] [US2] `contracts/orders.openapi.yaml`, `contracts/payments.openapi.yaml`, `contracts/orders-events.asyncapi.yaml`
- [ ] T032 [P] [US2] Concurrency test: 1,000 simultaneous purchase attempts across 100 items, zero double-sales (SC-003), in `app/tests/load/double_sell.py`
- [ ] T033 [US2] Reservation endpoint with conditional `available → reserved` update and 10-minute expiry sweeper in `app/services/listings/.../ReservationService.java`
- [ ] T034 [US2] Orders service: checkout orchestration, order states, refusal to buy own listing, in `app/services/orders/`
- [ ] T035 [US2] Payments: destination charge with application fee, ledger entries summing to the amount paid (FR-012), in `app/services/payments/app/charges.py`
- [ ] T036 [US2] Webhook handler with unique Stripe event IDs and validated transitions (FR-011) in `app/services/payments/app/webhooks.py`
- [ ] T037 [US2] Stripe CLI forwarder Deployment per namespace in `gitops/services/stripe-forwarder/`
- [ ] T038 [US2] Late-payment handling: refund when payment succeeds after reservation expiry, in `app/services/orders/app/reconcile.py`
- [ ] T039 [US2] Publish `order.paid` and `order.failed` to the `orders` exchange with trace context in message headers
- [ ] T040 [US2] Notifications worker: quorum queue, retry with backoff, dead-letter after 5 attempts (FR-016, FR-017), seller sale email and buyer confirmation (FR-015) over SMTP to Mailpit, in `app/services/notifications/`
- [ ] T041 [US2] BFF checkout and order-confirmation pages
- [ ] T042 [US2] GitOps manifests for Orders and Notifications

## Phase 5: User Story 5 - Follow one purchase across every service (Sprint 3, P2)

**Independent Test**: one purchase's trace, found by order ID, spans every service including the queued email.

- [ ] T043 [P] [US5] Add `order_id` as a span attribute and log field in every service
- [ ] T044 [US5] OTel Collector pipelines to Tempo, Loki and Prometheus; Grafana data source links from traces to logs
- [ ] T045 [US5] Argo CD notifications posting change events (service, version, env, time) to Loki, in `gitops/platform/argocd-notifications/`
- [ ] T046 [P] [US5] One Grafana dashboard per service (RED metrics) plus a checkout-path dashboard, as code in `gitops/platform/kube-prometheus-stack/dashboards/`

## Phase 6: User Story 6 - Realistic traffic whenever the platform runs (Sprint 3, P2)

**Independent Test**: a 4-hour session shows non-zero traffic in every 5-minute window for every service.

- [ ] T047 [US6] Locust traffic generator with browse, search, list and buy tasks and a compressed daily rate cycle (2 hours by default), in `app/tools/traffic/`
- [ ] T048 [US6] Synthetic user pool created in the prod realm; test cards only
- [ ] T049 [US6] Deploy the generator to `sv-prod` with its rate in a ConfigMap

## Phase 7: User Story 4 - Ship a change to prod through review (Sprint 3, P2)

**Independent Test**: a response-field change reaches dev with no manual step and prod only after an approved PR; a revert restores the previous version.

- [ ] T050 [US4] Branch protection and CODEOWNERS on `gitops/services/*/overlays/prod`
- [ ] T051 [US4] Demonstrate a blocked release: a deliberately vulnerable base image fails Trivy and nothing deploys; record evidence
- [ ] T052 [US4] Demonstrate rollback by `git revert` of a promotion commit; record timing

## Phase 8: User Story 3 - Rebuild the platform from Git (Sprint 3, P1)

**Independent Test**: destroy everything on the mini, one command, working purchase in under 30 minutes.

- [ ] T053 [US3] CloudNativePG scheduled backups to MinIO plus an on-demand `Backup` created by `make down`; restore a `Cluster` from backup during the drill
- [ ] T054 [US3] Write `specs/001-marketplace-local-cloud/quickstart.md`: empty machine to first purchase
- [ ] T055 [US3] Run the rebuild drill through Jenkins (destroy, apply, restore, purchase); record the time in `infra/docs/runbooks/rebuild.md`

## Phase 8b: User Story 7 - Add a new service from the template (Sprint 3, P3)

**Independent Test**: a generated "hello" service is healthy in dev with a dashboard after one merged pull request.

- [ ] T066 [US7] Copier template `app/templates/service-fastapi/` producing code, Dockerfile, tests, workflow and a kustomize base with OTel, `/healthz`, `/metrics` and policy-compliant defaults (FR-026)
- [ ] T067 [US7] Generate `hello` from the template, merge one PR, time it against SC-009, then remove it

## Phase 9: Polish and Gate 1 release

- [ ] T061 [P] JWT validation middleware in every service, rejecting missing or expired tokens (FR-003)
- [ ] T062 [P] Non-root `securityContext`, read-only root filesystem where possible, and a dedicated ServiceAccount per service in `gitops/services/*/base` (Constitution VI)
- [ ] T065 Install Kyverno via `gitops/platform/kyverno/` with enforce policies: non-root, requests and limits required, images only from the project's GHCR namespace (FR-027); run the same policies with `kyverno apply` in the GitOps repo's `checks` workflow; prove SC-010 with a folder of deliberately bad manifests
- [ ] T063 [P] Timed SC-001 check: onboarding under 5 minutes, listing under 2 minutes, recorded in the retro

- [ ] T056 [P] Notification-outage drill for SC-007 (stop Notifications 30 minutes, confirm delivery within 5 minutes of recovery)
- [ ] T057 [P] SC-002 load check at the baseline traffic rate; record p95 checkout latency
- [ ] T058 Build Listings in Jenkins as well as GitHub Actions; collect build time, setup effort and failure handling for the comparison article
- [ ] T059 Write `infra/sprints/sprint-3/verify_sprint3.sh` covering SC-001 to SC-007 where automatable
- [ ] T060 Write the Gate 1 case study and the "Jenkins or GitHub Actions?" article; ADRs 0003 (Stripe Connect via CLI forwarder), 0004 (namespaces, not clusters), 0005 (CloudNativePG over Crossplane for in-cluster databases) and 0006 (policy in CI and at admission)

---

## Dependencies and Execution Order

- Phase 1 → Phase 2 → everything else. Phase 2 blocks all stories.
- US1 (Phase 3) before US2 (Phase 4): a purchase needs a published listing.
- US5, US6 and US4 (Phases 5–7) can run in parallel once US2 is done.
- US3 (Phase 8) runs last, because the rebuild drill must include every service and its data.
- US7 (Phase 8b) needs only Phase 2 and T065, so it can run alongside Phases 5–7.
- Within a phase, tasks marked [P] touch different files and can run side by side.

## MVP Scope

Phases 1–4: a working marketplace on a platform that rebuilds from Git. Phases 5–9 complete Gate 1.
