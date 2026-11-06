Sorted Vintage — Sprint 2 Actionable Engineering Specification
Document Status: Draft for review
Target Release: Sprint 2, Seller Lists an Item (Nov 6 – Nov 19, 2026)
Author: Platform Engineering
Source: specs/001-marketplace-local-cloud/tasks.md, Phase 3 (User Story 1, T033–T052), T113 and T115–T120

1. Executive Summary & Sprint 2 Objective

Sprint 2 delivers User Story 1, the first half of the MVP: a visitor signs up, completes Stripe-hosted payout onboarding in test mode, and publishes a listing with photos that anyone can find. It adds two services on the Sprint 1 platform: Listings (Spring Boot, the first JVM service) and Payments (FastAPI, from the template), each with its own database in `sv-dev` and `sv-prod`. The BFF gains sign-in through Keycloak and its pages, and gets an Ingress, so the marketplace is reachable at `https://dev.sortedvtg.lan:8443` for the first time. A Stripe CLI forwarder inside the cluster delivers connected-account events without opening any inbound port. A seed job fills dev with demo sellers and 50 listings.

Scope decision (2026-11-05): Sprint 2 is User Story 1 only. User Story 2 (purchase, orders, payouts, emails) moves entirely to Sprint 3, and with it the purchase checks of T075, which now land in `verify_sprint3.sh`. Sprint 2 ends with `verify_sprint2.sh` checking User Story 1 (T115).

Sprint Objective
On a fresh dev environment, a new account signs up, completes onboarding and publishes a listing with two photos, and a signed-out visitor finds it by brand within 5 seconds (quickstart step 2, SC-001), with every Argo CD Application `Synced` and `Healthy` and `verify_sprint2.sh` green in Jenkins.

Decisions carried in
- Connected accounts use Accounts v2 with `dashboard: none` and Stripe-hosted onboarding (research R17, spike T009). Express accounts are not available to this platform.
- Stripe events reach the cluster through `stripe listen` running inside it (research R4); events missed while the lab is off are reconciled every 5 minutes (R5).
- The bff client's user tokens carry the audiences `listings`, `orders` and `payments`; services check their own audience and the BFF checks `azp == "bff"` (T025 spike).
- Keycloak imports a realm file only once. Realm and client changes are never made by hand in the live realm (Principle I): T120 adds a Job that applies them from Git on every sync, before any Sprint 2 client change.
- Every app image comes from `ghcr.io/rclaye/` (Kyverno, T026), so the Stripe CLI image is mirrored there.
- One ticket per pull request where possible; application code is written in the app chat (`src/sorted-vintage-app`), manifests and verification in the main chat. Each ticket says which repositories it touches.

2. Lab Changes in Sprint 2

| Added | Where | Memory budget (plan) |
| --- | --- | --- |
| Listings (Spring Boot 3, Java 21), one replica per environment | `sv-dev`, `sv-prod`, databases `listings` on the existing `pg` clusters, photos in each Garage bucket `photos` | 0.4 GB each |
| Payments (FastAPI), one replica per environment | `sv-dev`, `sv-prod`, database `payments` | 0.15 GB each |
| Stripe forwarder, two `stripe listen` containers | `sv-dev`, `sv-prod` | part of 0.4 GB with ingress |
| BFF Ingress for `dev.sortedvtg.lan` and `prod.sortedvtg.lan` | Traefik | none |
| Seed job (Argo CD PostSync hook) | `sv-dev` only | runs and exits |
| Keycloak config Job (keycloak-config-cli, PostSync hook) | `keycloak` | runs and exits |

Measured before the sprint: 6.2 GiB of pods (Sprint 1 retro). Expected after: about 7.5 GiB, still well under the 11 GB line. Ticket 2.8 measures it.

3. Actionable Engineering Tickets & Implementation Specs

Ticket 2.1 — Retire the Sprint's Risks First (T052, spikes)
Owner: Platform Engineer
Repos: infra (`sprints/sprint-2/spikes.md`)
Story: As the platform owner, I want the assumptions User Story 1 rests on tested before code depends on them, as Sprint 1 did.

Implementation Requirements:
- T052 Onboarding redirect: with the Stripe CLI as `bot`, create a test v2 account and an Account Link whose `return_url` and `refresh_url` are `https://dev.sortedvtg.lan/sell/onboarding`, complete onboarding in the Air's browser through the SSH tunnel, and record whether the browser lands back on the lab. If it does not, T043 uses `https://localhost:8443/sell/onboarding`. Close the test account afterwards.
- JVM on the lab: build a minimal Spring Boot 3 / Java 21 image for `linux/arm64`, run it on a throwaway cluster `sv-spike` with the Kyverno policies, and record its working set at idle and the startup time. Settle the heap flags (`-XX:MaxRAMPercentage`) and the memory limit Listings will use against the 0.4 GB budget.
- Seller token for scripts: decide how `verify_sprint2.sh` and the seed job obtain a seller's access token. Options: a dev-only Keycloak client with direct-access grants, limited to `sv-dev`; or the script driving the BFF login form. Either way the verify seller is one dedicated `sv-dev` user declared through T120, and its password is generated into `secrets.auto.tfvars` and reaches `sv-dev` as a Terraform-created Secret, never in Git. Record the choice and why; prod is only ever checked read-only.
- Onboarding without a browser: done, and it cannot be done. Stripe refuses an API-side terms acceptance for accounts where it collects requirements, so each seed seller and the verify seller is onboarded once by hand in the dev sandbox and its account then stays ready (spikes.md).
- keycloak-config-cli (T120): on `sv-spike`, import the realms, change a client in the realm file, and confirm the Job applies it on the next sync and leaves users alone.
- Keycloak check: confirm in the live `sv-dev` realm that the `bff` client's redirect URIs cover `https://dev.sortedvtg.lan:8443/auth/callback`, and that a registration email reaches Mailpit.

Acceptance Criteria Verification:
- `sprints/sprint-2/spikes.md` records the redirect result, the JVM memory and flags, the token decision, browser-free onboarding, the keycloak-config-cli result and the Keycloak check.
- No change to the lab cluster beyond reads; spikes run on `sv-spike`, deleted afterwards.

Ticket 2.2 — Groundwork: Java in CI, the BFF Ingress and Keycloak from Git (T116, T117, T118, T120)
Owner: Platform Engineer
Repos: app (`.github/workflows/build.yml`), gitops (`services/bff`, `platform/keycloak`), infra (`jenkins/Jenkinsfile`)
Story: As a developer, I want a Java service to travel the same delivery path as the Python ones, and the marketplace to have an address.

Implementation Requirements:
- T116 Extend `build.yml` so a service with a `build.gradle.kts` builds with Gradle on the arm64 runner (tests, then image), runs Trivy and the SonarQube Cloud scan exactly as Python services do, and hands its tag to gitops through `sv-deployer`. Create SonarQube Cloud projects `rclaye_sv-listings` and `rclaye_sv-payments`, each with its `sonar-project.properties`.
- T117 Ingress for the BFF in `gitops/services/bff/overlays/{dev,prod}`: hosts `dev.sortedvtg.lan` and `prod.sortedvtg.lan` on Traefik with the default TLS certificate.
- T118 Jenkins `verify` runs the newest `sprints/sprint-*` folder that contains its `verify_sprintN.sh` (done in the planning pull request), so a sprint folder can land before its script.
- T120 keycloak-config-cli as a `PostSync` Job in `gitops/platform/keycloak/`, applying the realm files' clients, scopes and user profile on every sync; then the `sv-dev` verify seller and the seed client are added through it.

Acceptance Criteria Verification:
- A pull request that adds a stub Gradle service shows build, Trivy and the SonarQube Cloud quality gate; after merge its dev tag reaches gitops with no manual step.
- `https://dev.sortedvtg.lan:8443/healthz` answers 200 from the Air's browser through the tunnel.
- `infra-terraform` stays green with `sprints/sprint-2/` present and no `verify_sprint2.sh` yet.
- A client setting changed in the realm file reaches the live `sv-dev` realm after one sync, with no admin-console edit.

Ticket 2.3 — Listings Service and Its Data (T035, T036, T050 listings)
Owner: Application Engineer
Repos: app (`services/listings`), gitops (`services/listings`)
Story: As a seller, I need a service that stores my listings and photos durably, so that what I publish survives restarts and rebuilds.

Implementation Requirements:
- T035 `services/listings/`: Spring Boot 3, Java 21, Gradle; resource server for Keycloak JWTs with audience `listings`; `/healthz` and `/metrics`; OpenTelemetry Java agent to the collector; JSON logs with the fields in `contracts/README.md`; non-root `Dockerfile`; the heap flags from Ticket 2.1.
- T036 Flyway `V1__listings.sql`: Seller profile, Listing (with the generated `search_vector` and its GIN index) and Photo, with the limits and enums in tasks.md.
- T050 (listings part) `gitops/services/listings/{base,overlays/dev,overlays/prod}`: credentials from `pg-listings-app`, S3 settings from `s3-photos`, the Keycloak issuer and JWKS URL per environment, requests and limits that pass Kyverno.

Acceptance Criteria Verification:
- `listings-dev` and `listings-prod` are `Synced` and `Healthy`; `/healthz` answers in both namespaces; Flyway reports `V1` applied.
- Its metrics appear in Prometheus and a request's trace in Tempo.

Ticket 2.4 — Listings Features: Drafts, Photos, Search (T033, T037–T041)
Owner: Application Engineer
Repos: app (`services/listings`)
Story: As a seller I create a listing with photos; as a visitor I find it by text, brand, size and price without signing in (FR-004 to FR-008).

Implementation Requirements:
- T033 first: contract tests for every Listings route in `contracts/listings.openapi.yaml` except reservations (JUnit 5, Testcontainers Postgres and Garage). They fail before T037.
- T037 create, get, edit, delete with the `If-Match` version check and the `listing_locked` rule; T038 photo upload with type detection from bytes, 10 MB and 8-photo limits, `pending` then `stored`; T039 hourly cleanup of `pending` photos; T040 browse and search with cursor pagination; T041 public seller profile.

Acceptance Criteria Verification:
- T033 passes in CI, with the SonarQube Cloud gate green.
- A `.txt` renamed to `.jpg` gets 415 `photo_type_rejected` and an 11 MB image 413 `photo_too_large`; neither leaves an object in Garage.

Ticket 2.5 — Payments: Onboarding and Connect Events (T034, T042–T045, T049, T050 payments)
Owner: Application Engineer, Platform Engineer for T049
Repos: app (`services/payments`), gitops (`services/payments`, `services/stripe-forwarder`)
Story: As a seller, I complete Stripe-hosted onboarding once, and the marketplace knows when I can be paid (FR-014).

Implementation Requirements:
- T034 first: contract tests for the onboarding link, payout status and the Connect webhook.
- T042 service from the template with Alembic `0001_connect`; T043 onboarding link and payout status on Accounts v2 (R17), using the URL settled in Ticket 2.1; T044 the Connect webhook with signature check and the idempotent event inbox; T045 reconciliation at startup and every 5 minutes.
- T049 `gitops/services/stripe-forwarder/`: one Deployment per namespace, two `stripe listen` containers (R4), the API key from each environment's `stripe` Secret. The image comes from `app/.github/workflows/mirror.yml`, which copies a pinned upstream digest to `ghcr.io/rclaye/stripe-cli` after a Trivy scan; the manifests pin that digest.
- T050 (payments part) manifests with `pg-payments-app` and the `stripe` Secret.

Acceptance Criteria Verification:
- A request with a bad `Stripe-Signature` gets 400 and stores nothing; a replayed event is a no-op.
- After test onboarding, payout status turns `ready` through the forwarder; with the forwarder stopped, it turns `ready` within 5 minutes through reconciliation.

Ticket 2.6 — Publish, Sign-In and the Pages (T046, T047, T048)
Owner: Application Engineer
Repos: app (`services/listings`, `services/bff`)
Story: As a visitor I sign up and sign in; as a seller I publish only once onboarding is complete (FR-001, FR-014).

Implementation Requirements:
- T046 `POST /listings/{id}/publish`: 1–8 stored photos, payout status `ready` from Payments with a `listings` client-credentials token, then `available`.
- T047 BFF auth: code flow with PKCE, Keycloak registration, HTTP-only `Secure` `SameSite=Lax` session cookie, CSRF tokens, `POST /logout`; check `azp == "bff"`.
- T048 the US1 pages in `contracts/bff-pages.md`: `/`, `/search`, `/items/{id}`, `/sellers/{sub}`, `/sell` and its form posts, `/sell/onboarding`; publish redirects to onboarding on `payout_onboarding_required`.

Acceptance Criteria Verification:
- Quickstart step 2 passes by hand in dev, with the times recorded: publishing after onboarding under 2 minutes, onboarding under 5 minutes, the listing in browse within 5 seconds (SC-001, T113).

Ticket 2.7 — Seed Data (T051)
Owner: Application Engineer
Repos: app (`tools/seed`), gitops (`services/seed`)
Story: As the operator, I want a fresh dev environment to look like a marketplace, so that demos and later traffic have something to work on.

Implementation Requirements:
- T051 Argo CD PostSync hook in `sv-dev`: demo sellers in Keycloak with onboarded test connected accounts, 50 listings with photos, idempotent on re-run. Users are created through the seed client declared by T120. Each demo seller is onboarded once by hand in the dev sandbox (Stripe refuses an API-side terms acceptance, Ticket 2.1), and the seed job links the Keycloak user to that existing account.

Acceptance Criteria Verification:
- After a sync, browse in dev shows 50 seeded listings; running the hook again changes nothing.

Ticket 2.8 — Verify and Measure (T115, T119)
Owner: Platform Engineer
Repos: infra (`sprints/sprint-2`, `docs/verification-log.md`)
Story: As the platform owner, I want User Story 1 checked by a script on every Jenkins build, and the memory budget re-measured with real services.

Implementation Requirements:
- T115 `sprints/sprint-2/verify_sprint2.sh`, after T046 and T051. Both modes first run `verify_sprint1.sh`, then read-only checks: Listings and Payments health in both namespaces, the BFF through its Ingress (with the mkcert CA), the forwarder ready, the seeded listings searchable. From the Air only, never in the Jenkins stage: bad Stripe signatures refused on both webhooks, and in `sv-dev` a scripted draft, two photos and publish by the verify seller that appears in search within 5 seconds (T113) and is then deleted, plus bad photo type and size refused. Prod is read-only.
- T119 Re-measure memory as in T032, and write `sprints/sprint-2/sprint2_retro.md`; add every acceptance check above to `docs/verification-log.md`.

Acceptance Criteria Verification:
- `verify_sprint2.sh` passes from the Air (all checks) and as the Jenkins `verify` stage (read-only checks).
- The retro records memory by component next to the plan, and the verification log has a row for every Sprint 2 acceptance check.

4. Sprint Verification

Run `sprints/sprint-2/verify_sprint2.sh` from the MacBook Air with the lab up for every check. Jenkins runs it with `MINI=local` at the end of every `infra-terraform` build once it is on `main`, and in that mode it only reads, as the plan's Complexity Tracking allows. From the Air it also makes one scripted publish in `sv-dev` by the verify seller and deletes it again; it never writes to prod. Quickstart step 2 is run once by hand for the SC-001 timings, which the script cannot measure through Stripe-hosted onboarding.

5. Out of Scope for Sprint 2

User Story 2 and everything it needs: Orders, Notifications, reservations and the purchase flow, the payment page, the ledger, emails to sellers, and the T075 purchase checks (all Sprint 3). Also the traffic generator (US6), the rebuild drill with restore (US3), dashboards beyond the stack's defaults, and Tailscale.
