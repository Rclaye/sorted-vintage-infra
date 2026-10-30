# Tasks: Sorted Vintage Marketplace on the Local Cloud

**Input**: Design documents from `specs/001-marketplace-local-cloud/`: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/README.md), [quickstart.md](./quickstart.md)
**Prerequisites**: plan.md and spec.md (required); research, data model, contracts and quickstart are complete (T005, T006)

**Tests**: included. The plan's Testing section asks for contract tests on every service API, the SC-002 and SC-003 load tests, and a `verify_sprintN.sh` per sprint.

**Accepted deviations (2026-10-29)**: single-node Kind ([research R1](./research.md#r1-kind-topology-and-stopstart-sessions)) and SSH on the home network instead of Tailscale, with ingress bound to loopback ([research R2](./research.md#r2-reaching-the-lab-ingress-ports-and-principle-vi)). Both are tracked in the plan's Complexity Tracking table.

## Format: `- [ ] T### [P?] [US#?] Description with path`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[US#]**: the user story the task serves; setup, foundational and polish tasks carry none
- Paths are prefixed by repository: `infra/`, `app/`, `gitops/`. Paths under `specs/` are in `infra/`.
- Field rules quoted in a task come from [data-model.md](./data-model.md); API shapes come from the named contract file.

**Task IDs**: T103–T106 were added after generation and placed where they run. They are numbered after T102 so that existing references stay valid.

**Sprint mapping**: Phases 1–2 and T080 = Sprint 1 · Phase 3 and Phase 4 up to T079 = Sprint 2 · the rest of Phase 4 through Phase 9 = Sprint 3 · Phase 10 = Gate 1 release

---

## Phase 1: Setup (Sprint 0 / start of Sprint 1)

**Purpose**: repositories, design documents and the spikes that confirm research decisions before code depends on them.

- [x] T001 Create repositories `sorted-vintage-infra`, `sorted-vintage-app`, `sorted-vintage-gitops` with README, LICENSE, `checks` workflow and the `protect-main` ruleset (Sprint 0, Ticket 0.2)
- [x] T002 Add `.gitignore` and `.pre-commit-config.yaml` with gitleaks in all three repos (Sprint 0, Ticket 0.2)
- [x] T003 Commit the Spec Kit workspace to `infra/.specify/` and `infra/specs/` (Sprint 0, Ticket 0.5; Specify CLI 1.2.5 scaffold added on `chore/spec-kit-init`)
- [x] T004 Write `infra/docs/adr/0001-local-kind-instead-of-eks.md` and `infra/docs/adr/0002-git-is-the-only-path-to-the-cluster.md`
- [x] T005 Write `specs/001-marketplace-local-cloud/research.md`
- [x] T006 Write `specs/001-marketplace-local-cloud/data-model.md`, `contracts/` and `quickstart.md`
- [ ] T007 [P] Add `terraform_fmt` and `terraform_validate` hooks (antonbabenko/pre-commit-terraform) to `infra/.pre-commit-config.yaml`; add `ruff`, `ruff-format` and `hadolint` hooks to `app/.pre-commit-config.yaml`; add `check-jsonschema` for Kubernetes YAML to `gitops/.pre-commit-config.yaml`; run `pre-commit autoupdate` in each repo as one PR per repo (closes the Sprint 0 retro follow-up)
- [ ] T008 Spike R1: on the mini, create a one-node Kind cluster, deploy a pod with a PVC that writes a file, run `docker stop` then `docker start` on the node container, and confirm the API server, the pod and the file return; record commands and result in `infra/sprints/sprint-1/spikes.md`. If it fails, stop and revisit research R1 before T010
- [ ] T009 [P] Spike R3/R4: create Stripe sandboxes `sorted-vintage-dev` and `sorted-vintage-prod` with Connect enabled; run `stripe listen --forward-to … --forward-connect-to …` against a local echo server, trigger `payment_intent.succeeded` and `account.updated`, and record in `infra/sprints/sprint-1/spikes.md` whether both streams use the same signing secret

---

## Phase 2: Foundational (Sprint 1, blocks every story)

**Purpose**: the cluster, GitOps delivery, shared platform components, policy, the service template and the session commands.

**⚠️ CRITICAL**: no user story work starts until this phase is complete.

**Checkpoint**: one `terraform apply` on the mini ends with Argo CD healthy, Kyverno enforcing, and a stub BFF answering at `https://dev.sortedvtg.lan:8443/healthz` through the SSH tunnel.

### Infrastructure (infra)

- [ ] T010 Write `infra/terraform/modules/kind-cluster/` (cluster name `sorted-vintage`; one control-plane node that runs workloads; `extraPortMappings` for 80 and 443 with `listenAddress` from variable `ingress_listen_address`, default `"127.0.0.1"`; an `extraMounts` entry mapping host path variable `lab_data_dir` to `/var/lab-data` for MinIO) and `infra/terraform/cluster/main.tf` using it with the `tehcyx/kind` provider
- [ ] T011 Write `infra/terraform/modules/argocd-bootstrap/` (Helm release of Argo CD in namespace `argocd`, plus an `Application` pointing at `gitops/bootstrap/root-app.yaml`) and `infra/terraform/bootstrap/main.tf`
- [ ] T012 Write `infra/terraform/modules/secrets/` creating Kubernetes Secrets in `sv-dev` and `sv-prod` from `infra/terraform/bootstrap/secrets.auto.tfvars` (git-ignored): each environment's Stripe secret key, publishable key and webhook signing secret(s) from its own sandbox; database passwords; and the mkcert `*.sortedvtg.lan` certificate and key as a `kubernetes.io/tls` Secret in `ingress-nginx`. Commit `infra/terraform/bootstrap/secrets.auto.tfvars.example` with placeholder values only
- [ ] T013 Write `infra/Makefile` targets `up` (start the Kind node container, then wait until every Argo CD Application is `Synced` and `Healthy`, timeout 10 minutes), `down` (read-only: wait until each CloudNativePG `Cluster` reports continuous archiving as working and its last archived WAL is no older than 120 seconds, wait 60 more seconds, then stop the node container; it creates nothing in the cluster, [research R14](./research.md#r14-backing-up-at-session-end-without-writing-to-the-cluster)), `rebuild` (`terraform apply` for `cluster` then `bootstrap`, then wait for health) and `destroy` (FR-024, FR-018)
- [ ] T103 Jenkins controller as code on the MacBook Air ([research R15](./research.md#r15-ci-hosts-and-how-they-are-reached)): `infra/jenkins/plugins.txt` (configuration-as-code, workflow-aggregator, git, ssh-slaves, credentials-binding, pipeline-stage-view) installed with the Jenkins Plugin Installation Manager Tool, and `infra/jenkins/casc.yaml` (copied to `~/.jenkins/casc.yaml` by `infra/scripts/jenkins/air-setup.sh`) defining: credential `mini-agent-ssh` read from the file named by `SV_AGENT_KEY_FILE` with `${readFile:…}`; the node `mac-mini` labelled `lab`, launched over SSH to `ricomillzs-Mac-mini.local` with the known-hosts verification strategy and work directory `~/jenkins-agent`; zero executors on the controller; and the pipeline job `infra-terraform` from `infra/jenkins/Jenkinsfile`, polling SCM `H/5 * * * *`. No secret values in either file
- [ ] T104 Jenkins on the Air per [infra/docs/runbooks/jenkins.md](../../docs/runbooks/jenkins.md): run `infra/scripts/jenkins/air-setup.sh` on the Air and `infra/scripts/jenkins/authorize-agent-key.sh` on the mini; add `openjdk@21` to `infra/scripts/Brewfile` and install it on the mini; confirm `lsof -nP -iTCP:8080 -sTCP:LISTEN` on the Air shows `127.0.0.1:8080` only and that `ssh -i ~/.ssh/sv_jenkins_agent mac-mini java -version` works; record the result in `infra/sprints/sprint-1/spikes.md`
- [ ] T014 Write `infra/jenkins/Jenkinsfile` (fmt, validate, tfsec, plan, manual approval, apply; destroy behind a second approval), running on agent label `lab`; needs T103 and T104
- [ ] T015 [P] Write `infra/docs/runbooks/lab-session.md`: open the SSH tunnel `ssh -N -L 8443:127.0.0.1:443 mac-mini`, the `/etc/hosts` entries on the Air (`dev`, `prod`, `grafana`, `argocd`, `mail` `.sortedvtg.lan` → `127.0.0.1`), trusting the mkcert root CA, `make up` / `make down` on the mini, and starting and stopping Jenkins on the Air (`launchctl kickstart` / `launchctl kill TERM` for `com.sortedvintage.jenkins`)

### GitOps platform (gitops)

- [ ] T016 Write `gitops/bootstrap/root-app.yaml` (app-of-apps over `platform/`) and `gitops/bootstrap/services-appset.yaml`: an ApplicationSet with a Git directory generator over `services/*/overlays/*`, naming each app `<service>-<overlay>` and deploying to namespace `sv-<overlay>` (FR-025)
- [ ] T017 [P] Add `gitops/platform/cert-manager/` (Helm chart, CRDs enabled); it is required by the Barman Cloud Plugin
- [ ] T018 [P] Add `gitops/platform/ingress-nginx/` using the TLS Secret from T012 as the default certificate, with Ingress hosts `dev`, `prod`, `grafana`, `argocd` and `mail` under `sortedvtg.lan`
- [ ] T019 [P] Add `gitops/platform/kube-prometheus-stack/` with Prometheus retention sized to the memory budget and persistent volumes for Prometheus and Grafana (telemetry must survive sessions, FR-024)
- [ ] T020 [P] Add `gitops/platform/loki/` and `gitops/platform/tempo/` (single-binary mode, persistent volumes) and `gitops/platform/otel-collector/` receiving OTLP and exporting traces to Tempo, logs to Loki and metrics to Prometheus
- [ ] T021 [P] Add `gitops/platform/postgres/`: the CloudNativePG operator, the Barman Cloud Plugin, and per namespace (`sv-dev`, `sv-prod`) a `Cluster` with databases `listings`, `orders`, `payments`, `notifications`, an `ObjectStore` pointing at that namespace's MinIO bucket `backups`, continuous WAL archiving through the plugin with `archive_timeout: 60s` in `spec.postgresql.parameters`, and a daily `ScheduledBackup` with `method: plugin` and `immediate: true` (FR-023; research R10, R14). Record in `infra/sprints/sprint-1/spikes.md` which status field reports the last archived WAL time, for T013
- [ ] T022 [P] Add `gitops/platform/minio/` per namespace with its volume on the Kind `extraMounts` path `/var/lab-data/minio-<env>` and buckets `photos` and `backups` created by a declarative bucket job or the chart's provisioning values
- [ ] T023 [P] Add `gitops/platform/rabbitmq/`: the RabbitMQ Cluster Operator and Messaging Topology Operator, and a single-replica `RabbitmqCluster` per namespace with a persistent volume
- [ ] T024 [P] Add `gitops/platform/mailpit/` per namespace (SMTP on 1025, UI behind the `mail.sortedvtg.lan` Ingress)
- [ ] T025 [P] Add `gitops/platform/keycloak/` with realms `sv-dev` and `sv-prod` imported from realm JSON: registration enabled with email verification over Mailpit SMTP; user attribute `display_name` ("1–40 characters") issued as a token claim; confidential client `bff` (code flow with PKCE); client-credentials clients `orders`, `payments`, `listings`; an audience mapper per service
- [ ] T026 Add `gitops/platform/kyverno/` with enforce-mode policies in `gitops/policies/`: containers must run as non-root, must set CPU and memory requests and limits, and images must come from `ghcr.io/rclaye/`; add the same policies to the GitOps repo's `checks` workflow with `kyverno apply gitops/policies/ --resource <changed manifests>`; add `gitops/tests/policy/bad/` with one failing manifest per rule and `gitops/tests/policy/good/` with one passing manifest (FR-027, Constitution III)

### Service template and delivery path (app, gitops)

- [ ] T027 Write the Copier template `app/templates/service-fastapi/`: FastAPI app with `GET /healthz` (200 `{"status":"ok"}` when its database and queue are reachable, else 503) and `GET /metrics` (Prometheus, including `http_server_request_duration_seconds` by route and status); OTel SDK with OTLP export and `traceparent` propagation; JSON logs with `timestamp`, `level`, `service`, `env`, `trace_id`, `span_id`, `message`; JWT validation middleware that checks Keycloak signature, audience and expiry and returns 401 otherwise (FR-003); the error body `{"error": "<machine_code>", "message": "<human text>"}`; multi-stage `Dockerfile` running as a non-root user; pytest skeleton; and `deploy/` with a kustomize `base` and `overlays/{dev,prod}` that pass the T026 policies (FR-026; [contracts/README.md](./contracts/README.md))
- [ ] T028 Generate `app/services/bff/` from the template as a stub that serves `/healthz` and `/metrics`
- [ ] T029 Write `app/.github/workflows/build.yml`: for each changed `services/*`, run lint and tests, build `linux/arm64` on `ubuntu-24.04-arm`, run Trivy and fail on critical, push to `ghcr.io/rclaye/sv-<service>:<git-sha>`, then commit the new tag to `gitops/services/<service>/overlays/dev/kustomization.yaml` with a GitOps deploy key (no cluster credentials, Constitution I)
- [ ] T105 SonarQube Cloud free plan ([research R15](./research.md#r15-ci-hosts-and-how-they-are-reached)): create the organization `rclaye` bound to GitHub, install the SonarQube Cloud GitHub App on `sorted-vintage-app`, and turn off automatic analysis; create project `rclaye_sv-bff`, with one project `rclaye_sv-<service>` per service as each one is created; add `app/services/bff/sonar-project.properties` (project key, `sonar.sources=app`, `sonar.tests=tests`, `sonar.python.coverage.reportPaths=coverage.xml`), and the same file to the T027 template; add a `sonar` step to `app/.github/workflows/build.yml` after tests using `SonarSource/sonarqube-scan-action` (pinned to a release tag) with `projectBaseDir: services/<service>` and the repository secret `SONAR_TOKEN`, which you create in SonarQube Cloud and add in GitHub yourself; confirm the quality gate appears on a pull request
- [ ] T030 Write `gitops/services/bff/{base,overlays/dev,overlays/prod}` and `gitops/.github/workflows/promote.yml`, which opens a PR copying a service's dev image tag into its prod overlay
- [ ] T106 Write `infra/docs/adr/0008-jenkins-on-the-air-and-sonarqube-cloud.md`, and amend `infra/.specify/memory/constitution.md` (PATCH, 1.1.0 → 1.1.1): the hardware line becomes "MacBook Air M4 16 GB runs local models and the Jenkins controller", the line for the third laptop is removed, and code analysis uses SonarQube Cloud's free plan; update the Sync Impact Report
- [ ] T031 Write `infra/sprints/sprint-1/verify_sprint1.sh`: Argo CD apps `Synced` and `Healthy`, BFF `/healthz` returns 200 in both namespaces, every `gitops/tests/policy/bad/` manifest is rejected by `kubectl apply --dry-run=server`, and `terraform plan` reports no changes
- [ ] T032 Measure real memory use against the plan's budget (target about 9.2 GB of 12 GB) and record it in `infra/sprints/sprint-1/sprint1_retro.md`; if above 11 GB, scale dev services to zero when idle before cutting anything else

**Checkpoint**: foundation ready. User story work can begin.

---

## Phase 3: User Story 1 - Seller signs up and lists an item (Priority: P1, Sprint 2) 🎯 MVP part 1

**Goal**: a visitor signs up, completes test-mode payout onboarding, and publishes a listing with photos that anyone can find.

**Independent Test**: on a fresh environment, a new account completes onboarding and publishes a listing with two photos, and a signed-out visitor finds it by brand ([quickstart step 2](./quickstart.md#2-seller-lists-an-item-user-story-1-sc-001)).

### Tests for User Story 1

- [ ] T033 [P] [US1] Contract tests for every Listings route in [contracts/listings.openapi.yaml](./contracts/listings.openapi.yaml) except reservations, in `app/services/listings/src/test/java/com/sortedvintage/listings/ListingsContractTest.java` (JUnit 5, Testcontainers Postgres and MinIO)
- [ ] T034 [P] [US1] Contract tests for `POST /connected-accounts/me/onboarding-link`, `GET /connected-accounts/{account_sub}/payout-status` and `POST /webhooks/stripe-connect` in [contracts/payments.openapi.yaml](./contracts/payments.openapi.yaml), in `app/services/payments/tests/contract/test_connect.py`

### Implementation for User Story 1

- [ ] T035 [US1] Create `app/services/listings/` (Spring Boot 3, Java 21, Gradle): Spring Security OAuth2 resource server validating Keycloak JWTs for audience `listings`; `/healthz` and `/metrics` at those exact paths (Micrometer Prometheus); OpenTelemetry Java agent; JSON logs with the fields in [contracts/README.md](./contracts/README.md); non-root `Dockerfile`
- [ ] T036 [US1] Flyway migration `app/services/listings/src/main/resources/db/migration/V1__listings.sql` for Seller profile (`account_sub` UUID primary key, `display_name`, `sold_count` integer default 0, `created_at`), Listing (`title` "3–80 characters"; `brand` "1–40 characters", indexed; `category` enum `tops`, `bottoms`, `dresses`, `outerwear`, `shoes`, `accessories`; `size` "1–10 characters"; `condition` enum `new_with_tags`, `like_new`, `good`, `fair`; `price_cents` "100–1,000,000"; `description` "0–2,000 characters"; `status` enum `draft`, `available`, `reserved`, `sold`, `deleted`; `version` integer; `search_vector` tsvector generated from title, brand and description with a GIN index; `created_at`, `published_at`, `updated_at`) and Photo (`storage_key`, `content_type`, `size_bytes`, `position` "0–7; unique per listing", `state` enum `pending`, `stored`)
- [ ] T037 [US1] Listing create, get, edit and delete in `app/services/listings/src/main/java/com/sortedvintage/listings/listing/`: owner-only edits with `If-Match` version check (409 `version_conflict`); edits and deletes refused with 409 `listing_locked` while `status = reserved` or `sold`; the seller profile row created on first draft, with `display_name` copied from the token on each write (FR-004, FR-006)
- [ ] T038 [US1] Photo upload in `app/services/listings/src/main/java/com/sortedvintage/listings/photo/PhotoService.java`: detect type from file bytes and accept only `image/jpeg`, `image/png`, `image/webp` (415 `photo_type_rejected`); "at most 10,485,760" bytes (413 `photo_too_large`); at most 8 per listing (409 `photo_limit`); insert the row as `pending`, write `listings/<listing_id>/<photo_id>` to MinIO bucket `photos`, then set `stored` (FR-005)
- [ ] T039 [US1] Scheduled cleanup in `app/services/listings/src/main/java/com/sortedvintage/listings/photo/PendingPhotoCleanup.java` deleting `pending` photo rows and their objects older than one hour
- [ ] T040 [US1] Browse and search in `app/services/listings/src/main/java/com/sortedvintage/listings/search/SearchRepository.java`: only `available` listings, newest `published_at` first, `q` over `search_vector`, filters `brand`, `size`, `category`, `min_price_cents`, `max_price_cents`, cursor pagination with default limit 24 and maximum 60 (FR-007)
- [ ] T041 [US1] `GET /sellers/{account_sub}` returning the profile with its `available` and `sold` listings in `app/services/listings/src/main/java/com/sortedvintage/listings/seller/SellerController.java` (FR-008)
- [ ] T042 [US1] Generate `app/services/payments/` from the template; add Alembic migration `app/services/payments/migrations/versions/0001_connect.py` for Connected account (`account_sub` UUID primary key; `stripe_account_id` unique; `details_submitted`, `charges_enabled`, `payouts_enabled` booleans; `updated_at`) and Payment event (`stripe_event_id` primary key; `type`; `source` enum `webhook`, `connect_webhook`, `reconciliation`; `payment_intent_id` nullable; `payload` jsonb; `received_at`; `applied_at` nullable)
- [ ] T043 [US1] Onboarding in `app/services/payments/app/connect.py`: `POST /connected-accounts/me/onboarding-link` creates the Express account if missing and returns a fresh Account Link with `return_url` and `refresh_url` on `https://<env>.sortedvtg.lan/sell/onboarding`; `GET /connected-accounts/{account_sub}/payout-status` returns `ready` when `charges_enabled` and `payouts_enabled`, `pending` when a row exists, `none` otherwise (FR-014)
- [ ] T044 [US1] `POST /webhooks/stripe-connect` in `app/services/payments/app/webhooks.py`: verify `Stripe-Signature` (400 and store nothing if invalid), insert into the Payment event inbox (duplicate `stripe_event_id` is a no-op), return 200, and apply `account.updated` to Connected account
- [ ] T045 [US1] Onboarding reconciliation in `app/services/payments/app/reconcile.py`: at startup and every 5 minutes, refresh Connected account flags from Stripe for accounts that are not `ready` ([research R5](./research.md#r5-events-missed-while-the-lab-is-off))
- [ ] T046 [US1] `POST /listings/{listing_id}/publish` in Listings: require 1–8 `stored` photos (409 `photos_required`) and payout status `ready` from Payments using a `listings` client-credentials token (409 `payout_onboarding_required`); set `available` and `published_at` (FR-014)
- [ ] T047 [US1] BFF auth in `app/services/bff/app/auth.py`: Keycloak code flow with PKCE, sign-up through Keycloak registration, session in an HTTP-only, `Secure`, `SameSite=Lax` cookie, CSRF token on every state-changing form, `POST /logout` (FR-001)
- [ ] T048 [US1] BFF pages in `app/services/bff/app/templates/` and `app/services/bff/app/routes/`: `/`, `/search`, `/items/{listing_id}`, `/sellers/{account_sub}`, `/sell`, `POST /sell/listings`, `POST /sell/listings/{id}/photos`, `POST /sell/listings/{id}/publish` (redirect to onboarding on `payout_onboarding_required`) and `/sell/onboarding`, as listed in [contracts/bff-pages.md](./contracts/bff-pages.md)
- [ ] T049 [US1] Stripe CLI forwarder in `gitops/services/stripe-forwarder/{base,overlays/dev,overlays/prod}`: one Deployment per namespace running `stripe listen --api-key $STRIPE_SECRET_KEY --forward-to http://payments/webhooks/stripe --forward-connect-to http://payments/webhooks/stripe-connect`, image mirrored to `ghcr.io/rclaye/` so it passes the T026 image policy ([research R4](./research.md#r4-stripe-webhooks-without-inbound-internet))
- [ ] T050 [P] [US1] GitOps manifests `gitops/services/listings/` and `gitops/services/payments/` (`base`, `overlays/dev`, `overlays/prod`) with database credentials from CloudNativePG Secrets and Stripe keys from the T012 Secrets
- [ ] T051 [US1] Seed job in `app/tools/seed/` and `gitops/services/seed/` as an Argo CD PostSync hook: demo sellers in Keycloak with onboarded test connected accounts, 50 listings with photos, idempotent on re-run (US3 scenario 2)
- [ ] T052 [US1] Spike R6: confirm Stripe accepts the `https://dev.sortedvtg.lan/sell/onboarding` redirect in test mode; if not, switch the T043 URLs to `https://localhost:8443/sell/onboarding`; record the result in `infra/sprints/sprint-2/spikes.md`

**Checkpoint**: User Story 1 works on its own ([quickstart step 2](./quickstart.md#2-seller-lists-an-item-user-story-1-sc-001)).

---

## Phase 4: User Story 2 - Buyer purchases and the seller is notified (Priority: P1, Sprints 2–3) 🎯 MVP part 2

**Goal**: a buyer pays at the asking price in Stripe test mode, the item is sold exactly once, the ledger balances, and both parties get email.

**Independent Test**: buy one listing with a test card; the order is paid, the listing is sold, and the seller's email is in Mailpit ([quickstart step 3](./quickstart.md#3-buyer-purchases-it-user-story-2)).

### Tests for User Story 2

- [ ] T053 [P] [US2] Contract tests for the reservation routes in [contracts/listings.openapi.yaml](./contracts/listings.openapi.yaml), in `app/services/listings/src/test/java/com/sortedvintage/listings/ReservationContractTest.java`, including two concurrent `POST /listings/{id}/reservations` where exactly one returns 201
- [ ] T054 [P] [US2] Contract tests for [contracts/orders.openapi.yaml](./contracts/orders.openapi.yaml) in `app/services/orders/tests/contract/test_orders.py`, including `Idempotency-Key` replay, 403 `own_listing`, and `payment-result` replay on a final order
- [ ] T055 [P] [US2] Contract tests for `POST /payment-intents`, `POST /payment-intents/{id}/cancel`, `POST /webhooks/stripe` and `GET /orders/{order_id}/ledger` in `app/services/payments/tests/contract/test_payments.py`, using `stripe-mock` for the Stripe API
- [ ] T056 [P] [US2] Ledger property test in `app/services/payments/tests/unit/test_ledger.py`: for amounts 100–1,000,000 and fee percentages 0–100, `platform = round_half_up(amount × fee_pct / 100)`, `seller = amount − platform`, and the two always sum to the amount ([research R7](./research.md#r7-money-arithmetic-and-the-ledger))
- [ ] T057 [P] [US2] Message contract test in `app/services/notifications/tests/contract/test_orders_events.py` validating consumed messages against [contracts/orders-events.asyncapi.yaml](./contracts/orders-events.asyncapi.yaml) and asserting a redelivered `event_id` sends no second email
- [ ] T058 [P] [US2] Double-sell load test in `app/tests/load/double_sell.py` (k6 or Locust): 1,000 simultaneous purchase attempts across 100 items, then query Orders and fail if any listing has more than one `paid` order (SC-003); expose it as `make loadtest-double-sell ENV=dev` in `app/Makefile`

### Implementation for User Story 2

- [ ] T059 [US2] Flyway migration `V2__reservations.sql` and `app/services/listings/src/main/java/com/sortedvintage/listings/reservation/ReservationService.java`: Reservation (`buyer_sub` "Must differ from the listing's `seller_sub`", `order_id`, `expires_at` "`created_at + 10 minutes`", `state` enum `active`, `released`, `consumed`, partial unique index on `listing_id` where `state = active`); reserve with `UPDATE listing SET status='reserved' WHERE id=? AND status='available'` in the same transaction as the insert (409 `not_available` when zero rows, 403 `own_listing`); idempotent `consume` (listing → `sold`, increment `sold_count`; 409 `reservation_released` if not `active`) and `release` (listing → `available`) (FR-009)
- [ ] T060 [US2] Reservation expiry sweeper in `app/services/listings/src/main/java/com/sortedvintage/listings/reservation/ReservationSweeper.java`, releasing `active` reservations past `expires_at` every 30 seconds
- [ ] T061 [US2] Generate `app/services/orders/` from the template; Alembic migration `app/services/orders/migrations/versions/0001_orders.py` for Order (`amount_cents` integer; `fee_pct` numeric(5,2) default 10.00; `payment_intent_id` unique; `status` enum `pending`, `paid`, `failed`, `refunded`; `failure_reason`; `created_at`, `paid_at`, `closed_at`), an idempotency-key table, and Outbox message (`event_type`, `payload` jsonb, `traceparent`, `created_at`, `published_at` nullable)
- [ ] T062 [US2] `POST /orders` in `app/services/orders/app/checkout.py`: require `Idempotency-Key` (replay returns the same order); reserve through Listings with the buyer's token; create the PaymentIntent through Payments; on Payments 503, release the reservation and return 503 `payments_unavailable`; return the order and `client_secret`, never logging the secret. Also `GET /orders` and `GET /orders/{order_id}` (buyer or seller only) (FR-009, FR-013)
- [ ] T063 [US2] `POST /orders/{order_id}/payment-result` in `app/services/orders/app/payment_result.py`, accepting only a `payments` client-credentials token: `succeeded` → consume the reservation → `paid` with an `order.paid` outbox row; consume returns `reservation_released` → `refunded` with an `order.refunded` outbox row; `failed` or `canceled` → release → `failed` with an `order.failed` outbox row; results for a final order are recorded and ignored. Each state change and its outbox row commit in one transaction (FR-011)
- [ ] T064 [US2] Orders expiry handling in `app/services/orders/app/expiry.py`: every 30 seconds, `pending` orders past `reservation_expires_at` → call Payments cancel, release the reservation, mark `failed`
- [ ] T065 [US2] Outbox relay in `app/services/orders/app/outbox_relay.py`: publish unpublished rows to exchange `orders` with routing key `event_type` and publisher confirms, under the trace context restored from the row's `traceparent`; set `published_at` only after the confirm ([research R9](./research.md#r9-trace-context-over-rabbitmq))
- [ ] T066 [US2] PaymentIntents in `app/services/payments/app/charges.py`: `POST /payment-intents` creates a destination charge with `application_fee_amount = round_half_up(amount × fee_pct / 100)`, `transfer_data.destination` set to the seller's `stripe_account_id`, and the order ID as the Stripe idempotency key (409 `seller_not_ready`, 503 `provider_unavailable`); `POST /payment-intents/{id}/cancel` is idempotent (FR-010, FR-014)
- [ ] T067 [US2] `POST /webhooks/stripe` in `app/services/payments/app/webhooks.py` and the inbox worker in `app/services/payments/app/inbox_worker.py`: store `payment_intent.succeeded`, `payment_intent.payment_failed` and `payment_intent.canceled` with `source = webhook` and return 200; the worker applies each unapplied event to Orders with a `payments` client-credentials token, retrying with backoff until `applied_at` is set (FR-011)
- [ ] T068 [US2] Ledger and refunds in `app/services/payments/app/ledger.py`: Alembic migration for Ledger entry (`party` enum `platform`, `seller`; `account_sub` null for `platform`; `amount_cents`; `kind` enum `sale`, `refund`; unique `(order_id, party, kind)`); write the `sale` pair when Orders returns `paid`; when Orders returns `refunded`, issue a Stripe refund with `reverse_transfer` and `refund_application_fee` and write the negative `refund` pair; `GET /orders/{order_id}/ledger` (FR-012)
- [ ] T069 [US2] Payment reconciliation in `app/services/payments/app/reconcile.py`: at startup and every 5 minutes, for orders `pending` longer than 2 minutes, retrieve the PaymentIntent and store its outcome as an inbox event keyed `recon:<payment_intent_id>:<status>` with `source = reconciliation` ([research R5](./research.md#r5-events-missed-while-the-lab-is-off))
- [ ] T070 [US2] RabbitMQ topology as Messaging Topology Operator resources in `gitops/services/orders/base/messaging.yaml`: topic exchange `orders`, quorum queue `notifications.orders` with `delivery-limit` 5 bound to `order.paid` and `order.refunded`, dead-letter exchange `orders.dlx` and queue `notifications.orders.dead` (FR-017)
- [ ] T071 [US2] Generate `app/services/notifications/` from the template; Alembic migration for Notification (`event_id` unique with `template`; `template` enum `order_confirmation_buyer`, `item_sold_seller`; `attempts` "At most 5"; `state` enum `queued`, `sent`, `dead_lettered`; `last_error`; `created_at`, `sent_at`)
- [ ] T072 [US2] Notifications consumer in `app/services/notifications/app/consumer.py` with `opentelemetry-instrumentation-aio-pika`: for `order.paid` send the buyer confirmation and the seller sale email, for `order.refunded` send the buyer a refund notice; look up addresses from Keycloak with a client-credentials token; SMTP to Mailpit; skip any `event_id` + `template` already `sent`; reject after the fifth failure so the message dead-letters and the row becomes `dead_lettered` (FR-015, FR-016, FR-017)
- [ ] T073 [US2] BFF checkout in `app/services/bff/app/routes/checkout.py` and templates: `POST /checkout/{listing_id}` generates the `Idempotency-Key`, shows the Payment Element with the environment's publishable key, and handles `not_available` and `own_listing`; `GET /orders/{order_id}` polls with HTMX until the order is final; `GET /orders` lists the buyer's orders
- [ ] T074 [P] [US2] GitOps manifests `gitops/services/orders/` and `gitops/services/notifications/` (`base`, `overlays/dev`, `overlays/prod`), with the platform fee percentage as a ConfigMap value defaulting to 10
- [ ] T075 [US2] Write `infra/sprints/sprint-2/verify_sprint2.sh`: listing publishes and is searchable, a scripted purchase with `pm_card_visa` ends `paid` with a balanced ledger and two emails in Mailpit, `pm_card_chargeDeclined` releases the item, and T058 reports zero double sales

**Checkpoint**: User Stories 1 and 2 both work; this is the MVP ([quickstart steps 2 and 3](./quickstart.md#3-buyer-purchases-it-user-story-2)).

---

## Phase 5: User Story 3 - Operator rebuilds the platform from Git (Priority: P1, Sprint 3)

**Goal**: one command takes an empty mini to a working purchase, with data restored from backup.

**Independent Test**: destroy everything, run `make rebuild`, and time it until every app is healthy and a purchase succeeds, under 30 minutes (SC-004; [quickstart steps 1 and 11](./quickstart.md#1-rebuild-from-nothing-user-story-3-sc-004)).

- [ ] T076 [US3] Add `RESTORE=latest` to `make rebuild` in `infra/Makefile`: it sets Terraform variable `postgres_bootstrap = "recovery"` in `infra/terraform/bootstrap`, which points the platform app-of-apps at `gitops/platform/postgres/overlays/recovery/`, whose `Cluster` uses `bootstrap.recovery` from the plugin `ObjectStore` on the persistent MinIO volume. The default `"initdb"` selects `overlays/initdb/`. Argo CD applies either one; nothing is applied to the cluster by hand (FR-023, Constitution I)
- [ ] T077 [US3] Add a `rebuild-drill` stage to `infra/jenkins/Jenkinsfile` (destroy, apply, restore, wait for health, scripted purchase) that records the elapsed time as a build artifact
- [ ] T078 [US3] Write `infra/docs/runbooks/rebuild.md` covering `make destroy`, `make rebuild RESTORE=latest`, what survives (MinIO volume on the host) and what does not
- [ ] T079 [US3] Run `make down` then `make up` with the mini powered on, confirm health in under 10 minutes with previous orders and dashboards present, and record it in `infra/sprints/sprint-3/sessions.md` (SC-008)

---

## Phase 6: User Story 4 - Operator ships a change to prod through review (Priority: P2, Sprint 3)

**Goal**: changes reach dev automatically and prod only through an approved pull request.

**Independent Test**: a response-field change reaches dev with no manual step and prod only after an approved promotion PR; reverting it restores the previous version ([quickstart step 5](./quickstart.md#5-ship-a-change-through-review-user-story-4)).

- [ ] T080 [US4] Prod approval gate per ADR-0002 (pulled into Sprint 1): create the GitHub Environment `prod` on `sorted-vintage-gitops` with the owner as required reviewer, from `infra/scripts/protect-prod.sh`; add `gitops/.github/workflows/prod-gate.yml`, which on every pull request runs a `prod-gate` job that passes at once when no file under `services/*/overlays/prod/` changed and otherwise runs in environment `prod`, so it passes only after the reviewer approves; add `prod-gate` to the required checks of the `protect-main` ruleset on the GitOps repo. PR approvals stay at zero, because GitHub does not let an author approve their own pull request
- [ ] T081 [US4] Demonstrate a blocked release: a branch with a base image carrying a known critical CVE fails Trivy in `build.yml` and publishes nothing; record evidence in `infra/sprints/sprint-3/evidence.md`
- [ ] T082 [US4] Demonstrate rollback by `git revert` of a promotion commit; record the time until prod runs the previous version in `infra/sprints/sprint-3/evidence.md`

---

## Phase 7: User Story 5 - Operator follows one purchase across every service (Priority: P2, Sprint 3)

**Goal**: from one order ID, find a single trace covering every service, its logs and its metrics.

**Independent Test**: look up a completed purchase's trace by order ID and confirm it spans every service, including the queued email, with linked logs ([quickstart step 4](./quickstart.md#4-follow-the-purchase-user-story-5-sc-005)).

- [ ] T083 [P] [US5] Add `order_id` as a span attribute and log field wherever an order is in scope, in `app/services/{bff,orders,payments,notifications}/app/telemetry.py` and `app/services/listings/src/main/java/com/sortedvintage/listings/telemetry/OrderIdFilter.java`
- [ ] T084 [US5] Trace continuity test in `app/tests/e2e/test_trace.py`: complete a purchase and assert, through the Tempo API, that one trace contains spans from BFF, Orders, Listings, Payments and the Notifications consume span; if the aio-pika instrumentor links instead of parenting, extract the context manually in `app/services/notifications/app/consumer.py` ([research R9](./research.md#r9-trace-context-over-rabbitmq), SC-005)
- [ ] T085 [US5] Grafana data sources in `gitops/platform/kube-prometheus-stack/values.yaml`: Tempo with trace-to-logs on `trace_id` and search by `order_id`, Loki with a derived field linking `trace_id` to Tempo
- [ ] T086 [US5] Change events in `gitops/platform/argocd-notifications/`: an `on-deployed` trigger that posts a Grafana annotation tagged `service`, `version`, `env` and writes the same fields as a JSON log line to Loki ([research R11](./research.md#r11-change-events-fr-021), FR-021)
- [ ] T087 [P] [US5] Dashboards as code in `gitops/platform/kube-prometheus-stack/dashboards/`: one RED dashboard per service and one checkout-path dashboard, each showing deployment annotations

---

## Phase 8: User Story 6 - The platform has realistic traffic whenever it runs (Priority: P2, Sprint 3)

**Goal**: steady, daily-shaped synthetic traffic for the whole session.

**Independent Test**: a 4-hour session shows non-zero traffic in every 5-minute window for every service and a growing order count ([quickstart step 12](./quickstart.md#12-traffic-runs-all-session-user-story-6)).

- [ ] T088 [US6] Locust generator in `app/tools/traffic/locustfile.py`: browse, search, list and buy tasks through the BFF routes; purchases confirm the PaymentIntent server-side with `pm_card_visa`, and a configurable share with `pm_card_chargeDeclined` ([research R6](./research.md#r6-payment-ui-and-synthetic-purchases))
- [ ] T089 [US6] `LoadTestShape` in `app/tools/traffic/shape.py` following a daily-shaped curve, with `BASE_RPS`, `PEAK_RPS` and `CYCLE_MINUTES` (default 120) from environment variables (FR-022)
- [ ] T090 [US6] Synthetic user pool: extend the seed job in `app/tools/seed/` to create 50 synthetic buyers and sellers in each realm, with credentials in a generated Secret the generator reads
- [ ] T091 [US6] Deploy the generator headless in `gitops/services/traffic/{base,overlays/dev,overlays/prod}`, with rates in each overlay's ConfigMap (lower in dev)

---

## Phase 9: User Story 7 - Operator adds a new service from the template (Priority: P3, Sprint 3)

**Goal**: a new service goes from template to healthy in dev with one pull request and no platform change.

**Independent Test**: generate `hello`, merge one PR, and see it healthy in dev with a dashboard in under 30 minutes ([quickstart step 9](./quickstart.md#9-add-a-service-from-the-template-user-story-7-sc-009)).

- [ ] T092 [US7] Extend the T027 template to generate `gitops/services/<name>/{base,overlays}` and a RED dashboard ConfigMap, so one PR to each repo is all a new service needs
- [ ] T093 [US7] Generate `hello` from the template, merge its PRs, time it against SC-009, record the result in `infra/sprints/sprint-3/evidence.md`, then remove it

---

## Phase 10: Polish and Gate 1 release

**Purpose**: measured success criteria, the full rebuild drill, and the write-ups.

- [ ] T094 [P] Timed SC-001 check (onboarding under 5 minutes, listing under 2 minutes), recorded in `infra/sprints/sprint-3/evidence.md`
- [ ] T095 [P] SC-002 load check at the baseline traffic rate for 15 minutes (`make loadtest-baseline ENV=dev` in `app/Makefile`); record p95 checkout latency excluding time on the payment page
- [ ] T096 [P] Notification outage drill for SC-007 ([quickstart step 7](./quickstart.md#7-notifications-outage-sc-007)); record delivery times after recovery
- [ ] T097 [P] Policy proof for SC-010 ([quickstart step 6](./quickstart.md#6-policy-holds-by-every-route-sc-010-fr-027)), recorded in `infra/sprints/sprint-3/evidence.md`
- [ ] T098 Run the full rebuild drill through Jenkins (T077), confirm SC-004, and record the time in `infra/docs/runbooks/rebuild.md`
- [ ] T099 Build Listings in Jenkins as well as GitHub Actions (Jenkins builds run on the mini agent; the controller on the Air runs none); collect build time, setup effort and failure handling for the comparison article
- [ ] T100 Write `infra/sprints/sprint-3/verify_sprint3.sh` covering SC-001 to SC-010 where automatable
- [ ] T101 [P] Write ADRs in `infra/docs/adr/`: 0003 (Stripe Connect through the CLI forwarder, one sandbox per environment), 0004 (namespaces, not clusters), 0005 (CloudNativePG with the Barman Cloud Plugin over Crossplane), 0006 (policy in CI and at admission), 0007 (single-node Kind, and the temporary SSH-only access until Tailscale)
- [ ] T102 Write the Gate 1 case study and the "Jenkins or GitHub Actions?" article in `infra/docs/case-studies/`

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1**: T008 must pass before T010; T009 must finish before T012 and T049.
- **Phase 2** depends on Phase 1 and blocks every story. Within it: T010 → T011 → T016; T012 needs T009; T021 needs T017 and T022; T026 before any service manifest; T027 → T028 → T030; T013 needs T021; T104 → T103 → T014; T105 needs T029.
- **Phases 3–9** depend on Phase 2.
- **Phase 10** depends on every story it measures.

### User story dependencies

- **US1** (Phase 3): only Phase 2.
- **US2** (Phase 4): needs US1, because a purchase needs a published listing and an onboarded seller (T043–T046, T049).
- **US3** (Phase 5): needs US2 for the purchase in its test; T076 needs only T021.
- **US4** (Phase 6): needs only Phase 2 (T029, T030). T080 is done in Sprint 1, as ADR-0002 requires; T081 and T082 come later because the demonstrations use a real service.
- **US5** (Phase 7): needs US2.
- **US6** (Phase 8): needs US2.
- **US7** (Phase 9): needs only Phase 2 (T026, T027).
- US4, US5, US6 and US7 can run in parallel once their dependencies are met.

### Within each story

- Tests first, and they should fail before implementation.
- Migrations and models before services, services before endpoints, endpoints before BFF pages, GitOps manifests last.

### Parallel opportunities

- Phase 1: T007 and T009 alongside T008.
- Phase 2: T015, T017–T025 are separate folders and run side by side once T016 exists.
- US1: T033 and T034 together; T050 alongside the BFF work.
- US2: T053–T058 together; Listings (T059–T060), Orders (T061–T065), Payments (T066–T069) and Notifications (T071–T072) are separate services and can proceed in parallel against the contracts.
- US5: T083 and T087 together.
- Phase 10: T094–T097 and T101 together.

## Parallel Example: User Story 2

```text
Contract tests together:
  T053 ReservationContractTest.java (listings)
  T054 test_orders.py (orders)
  T055 test_payments.py (payments)
  T056 test_ledger.py (payments)
  T057 test_orders_events.py (notifications)

Then services in parallel against the contracts:
  Listings:      T059 → T060
  Orders:        T061 → T062 → T063 → T064 → T065
  Payments:      T066 → T067 → T068 → T069
  Notifications: T070 → T071 → T072
```

## Implementation Strategy

### MVP first (User Stories 1 and 2)

1. Phase 1, including the T008 and T009 spikes.
2. Phase 2. Stop and run `verify_sprint1.sh`.
3. Phase 3 (US1). Stop and check quickstart step 2.
4. Phase 4 (US2). Stop and run `verify_sprint2.sh`. This is the MVP: a working marketplace on a platform delivered from Git.

### Incremental delivery

- US3 next, because the rebuild time is the first case-study metric.
- Then US4, US5, US6 and US7 in any order or in parallel.
- Phase 10 closes Gate 1.
