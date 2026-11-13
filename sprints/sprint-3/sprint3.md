Sorted Vintage — Sprint 3 Actionable Engineering Specification
Document Status: Draft for review
Target Release: Sprint 3, A Buyer Purchases (Nov 13 – Nov 26, 2026)
Author: Platform Engineering
Source: specs/001-marketplace-local-cloud/tasks.md, Phase 4 (User Story 2, T053–T075), T083, T113

1. Executive Summary & Sprint 3 Objective

Sprint 3 delivers User Story 2, the second half of the MVP: a signed-in buyer pays for a listing with a Stripe test card, the item is sold exactly once, the seller is paid through their connected account minus the platform fee, both sides get an email, and a failed or abandoned payment puts the item back on sale. It adds two services on the platform, Orders and Notifications (both FastAPI, from the template), each with its own database in `sv-dev` and `sv-prod`. Listings learns reservations, Payments learns charges, the ledger, refunds and the platform webhook the forwarder already sends to, and the BFF gets checkout.

Scope decision (2026-11-12, with Richard): the original Sprint 3 (User Stories 2 to 7 and Gate 1, about 42 tasks) is split in two. Sprint 3 is User Story 2 only, so the purchase path is built and proven before anything operational is layered on it. Sprint 4 takes User Stories 3 to 7, the log shipper (T125) and the Gate 1 release; it is outlined in section 6. `verify_sprint3.sh` checks User Story 2; the Gate 1 script covering SC-001 to SC-010 (T100) moves to Sprint 4 as `verify_sprint4.sh`, which runs `verify_sprint3.sh` first.

Sprint Objective
On dev, a buyer signed in through the BFF pays for a seeded listing with `pm_card_visa`: the order ends `paid`, the listing `sold`, the ledger balances (platform fee plus seller share equal the amount), and Mailpit holds the buyer's confirmation and the seller's sale email. `pm_card_chargeDeclined` leaves the listing available again, and 1,000 simultaneous attempts on 100 items sell none twice (SC-003). Every Argo CD Application is `Synced` and `Healthy`, and `verify_sprint3.sh` is green from the workstation and in Jenkins.

Decisions carried in
- Destination charges on Accounts v2 connected accounts, with `application_fee_amount` and `transfer_data.destination`, `automatic_payment_methods` and no `payment_method_types` (T009). The platform fee is a percentage, default 10, rounded half up (research R7).
- Stripe events reach the cluster through `stripe listen` inside it (R4). The platform session already forwards `payment_intent.succeeded` and `payment_intent.payment_failed` to `/webhooks/stripe`, which returns 404 until Ticket 3.5. Missed events are reconciled every 5 minutes (R5). The forwarder's output is redacted (gitops #54).
- An order's state change and its outbox row commit in one transaction; the relay publishes with confirms and carries the trace context in the row (R9). Consumers are idempotent by `event_id`.
- Users and clients come from the realm files through keycloak-config-cli (T120); nothing is changed by hand in the live realm.
- Prod gets each new service at 0 replicas until its first promotion, as Payments did (`first-prod-replicas`).
- Settings before images: when a new image needs new environment variables, the gitops PR merges first.
- One ticket per pull request where possible; a spike before anything risky reaches the lab (Sprint 2 lesson: the spike's shortcut is not the design).

2. Lab Changes in Sprint 3

| Added | Where | Memory (measured services as the yardstick) |
| --- | --- | --- |
| Orders (FastAPI), one replica per environment | `sv-dev`, `sv-prod` (0 until promoted), database `orders` on the existing `pg` clusters | about 80 to 100 MiB each |
| Notifications (FastAPI), one replica per environment | `sv-dev`, `sv-prod` (0 until promoted), database `notifications` | about 80 to 100 MiB each |
| RabbitMQ topology: exchange `orders`, quorum queue `notifications.orders`, dead-letter exchange and queue | each environment's RabbitMQ, by the Messaging Topology Operator | small |
| Keycloak clients for Orders, Payments and Notifications service tokens | realm files `sv-dev.json`, `sv-prod.json` | none |
| Listings reservations and sweeper, Payments charges, ledger, inbox worker | existing services | small |

Measured before the sprint: pods 8.29 GiB, node container 9.28 of 11.91 GiB (Sprint 2 retro). Expected after: pods about 8.7 GiB. Ticket 3.8 is **memory checkpoint 1** of the three in plan.md (trigger: pods' 95th percentile over 10 GiB; levers in the order plan.md gives).

3. Actionable Engineering Tickets & Implementation Specs

Ticket 3.1 — Retire the Sprint's Risks First (spikes)
Owner: Platform Engineer, Application Engineer
Repos: infra (`sprints/sprint-3/spikes.md`)
Story: As the team, we prove the risky parts of paying before building on them.

Implementation Requirements:
- **Destination charge in the dev sandbox:** a PaymentIntent for a seeded listing's seller (`demo-seller-1`), confirmed server-side with `pm_card_visa`, with `application_fee_amount` and `transfer_data.destination`; record the `payment_intent.succeeded` event's shape as it arrives through the forwarder, the transfer and the application fee. Then a refund with `reverse_transfer` and `refund_application_fee`. Find out why `stripe trigger` failed in the platform-hygiene spike (2026-11-12) before relying on it.
- **Payment Element on the BFF:** Stripe.js from `js.stripe.com` under the BFF's Content-Security-Policy (today `'self'` only, with Stripe allowed in `form-action`), at `https://dev.sortedvtg.lan:8443`; record exactly which `script-src`, `frame-src` and `connect-src` entries it needs.
- **Messaging Topology Operator:** an exchange, a quorum queue with `delivery-limit` and a dead-letter exchange in one environment's RabbitMQ from manifests, on `sv-spike` first.
- **Service tokens:** which realm clients Orders, Payments and Notifications need (client credentials, audiences `orders`, `listings`, `payments`; Notifications may only view users), applied by keycloak-config-cli on `sv-spike` first.

Acceptance Criteria Verification:
- Each spike has a result in `spikes.md` (pass, or the design change it forces) before the ticket that depends on it starts.

Ticket 3.2 — Contract Tests First (T053–T057)
Owner: Application Engineer
Repos: app
Story: As the team, we write down how the services talk to each other before writing the services.

Implementation Requirements:
- T053 reservation routes in Listings, including two concurrent `POST /listings/{id}/reservations` where exactly one returns 201.
- T054 Orders contract (`Idempotency-Key` replay, 403 `own_listing`, `payment-result` replay on a final order); T055 Payments contract with `stripe-mock`; T056 the ledger property test (R7); T057 the message contract, where a redelivered `event_id` sends no second email.
- T058, the double-sell load test, moved to Ticket 3.8 (decided 2026-11-13): it needs a scripted buyer who can pay, which depends on the checkout built in Ticket 3.7, and reuses `verify_sprint3.sh`'s scripted purchase.
- Tests that land before their code are strict xfails (pytest) or `@Pending` (JUnit), naming the task that will make them pass; a test that starts passing fails CI until its marker is removed. Orders and Notifications are generated from the template here (the first step of T061 and T071), so CI runs their tests.

Acceptance Criteria Verification:
- The tests exist and fail for the right reason (the routes are missing), and CI runs them on each PR.

Ticket 3.3 — Listings Reservations (T059, T060)
Owner: Application Engineer
Repos: app (`services/listings`)
Story: As a buyer, the item I am paying for is held for me, and only for me, for 10 minutes (FR-009).

Implementation Requirements:
- T059 `V2__reservations.sql` and `ReservationService`: reserve in one transaction with the conditional update (409 `not_available`, 403 `own_listing`), idempotent `consume` (listing `sold`, `sold_count` + 1) and `release`.
- T060 the sweeper releasing expired `active` reservations every 30 seconds.

Acceptance Criteria Verification:
- T053 passes, including the concurrent case; a listing reserved and not paid is available again after its reservation expires.

Ticket 3.4 — Orders Service (T061–T065, T070)
Owner: Application Engineer, Platform Engineer for T070
Repos: app (`services/orders`), gitops (`services/orders/base/messaging.yaml`)
Story: As a buyer, my order has one clear state from checkout to paid, failed or refunded (FR-011, FR-013).

Implementation Requirements:
- T061 the service from the template, `0001_orders` with the order, idempotency-key and outbox tables.
- T062 `POST /orders` (reserve with the buyer's token, create the PaymentIntent through Payments, release on 503, never log the client secret), `GET /orders`, `GET /orders/{id}`.
- T063 `payment-result` from Payments only, each state change and its outbox row in one transaction; T064 expiry every 30 seconds; T065 the outbox relay with publisher confirms and the restored trace context.
- T070 the topology from the Ticket 3.1 spike.

Acceptance Criteria Verification:
- T054 passes; an order's state change and its event are never seen apart (no event without the state, no state without the event after the relay runs).

Ticket 3.5 — Payments: Charges, Webhook, Ledger and Refunds (T066–T069)
Owner: Application Engineer
Repos: app (`services/payments`)
Story: As a seller, I am paid my share of each sale, and the platform keeps its fee, recorded so it always adds up (FR-010, FR-012).

Implementation Requirements:
- T066 `POST /payment-intents` (destination charge as spiked in 3.1, the order ID as Stripe's idempotency key, 409 `seller_not_ready`, 503 `provider_unavailable`) and idempotent cancel.
- T067 `POST /webhooks/stripe` (the forwarder's platform session starts getting 200 instead of 404) and the inbox worker applying events to Orders with retries.
- T068 the ledger (`sale` pair on `paid`, a Stripe refund and the negative `refund` pair on `refunded`) and `GET /orders/{id}/ledger`; T069 payment reconciliation every 5 minutes.
- A live call against the sandbox before the ticket closes (Sprint 2 lesson: fakes accepted requests Stripe refused).

Acceptance Criteria Verification:
- T055 and T056 pass; a bad `Stripe-Signature` on `/webhooks/stripe` gets 400; with the forwarder stopped, a paid order still turns `paid` within 5 minutes through reconciliation.

Ticket 3.6 — Notifications Service (T071, T072)
Owner: Application Engineer
Repos: app (`services/notifications`)
Story: As a buyer and as a seller, I get one email when an order is paid or refunded, never two (FR-015 to FR-017).

Implementation Requirements:
- T071 the service from the template and its Notification table; T072 the consumer (buyer confirmation and seller sale email on `order.paid`, a refund notice on `order.refunded`), addresses from Keycloak with a service token, SMTP to Mailpit, skip what was already sent, dead-letter after the fifth failure.

Acceptance Criteria Verification:
- T057 passes; a redelivered event sends nothing; a message that fails five times is in `notifications.orders.dead` and its row is `dead_lettered`.

Ticket 3.7 — Checkout in the BFF, the Manifests, and `order_id` Everywhere (T073, T074, T083)
Owner: Application Engineer, Platform Engineer for T074
Repos: app (`services/bff`, all services for T083), gitops (`services/orders`, `services/notifications`, BFF settings)
Story: As a buyer, I press Buy, pay with a card on the page, and see my order become paid.

Implementation Requirements:
- T073 `POST /checkout/{listing_id}` with the Payment Element (the CSP from 3.1), the order page polling with HTMX until final, and the buyer's orders.
- T074 gitops for Orders and Notifications (`base`, `overlays/dev`, `overlays/prod` at 0 replicas until promoted), with the fee percentage as a ConfigMap value, merged before the images that need the settings.
- T083 `order_id` as a span attribute and log field wherever an order is in scope (the trace test that uses it is T084 in Sprint 4).

Acceptance Criteria Verification:
- Quickstart step 3 by hand in dev: a purchase from a seeded listing ends `paid` and both emails are in Mailpit; a declined card shows an error and the listing stays available.

Ticket 3.8 — Verify and Measure (T058, T075, T113 in `verify_sprint3.sh`, memory checkpoint 1)
Owner: Platform Engineer
Repos: infra (`sprints/sprint-3`, `docs/verification-log.md`)
Story: As the platform owner, I want User Story 2 checked by a script on every Jenkins build, and the memory budget measured with the new services running.

Implementation Requirements:
- `sprints/sprint-3/verify_sprint3.sh` runs `verify_sprint2.sh` first. Reads, in both modes: Orders and Notifications health in both namespaces, the RabbitMQ topology present, the forwarder's platform session answered 200. From the workstation only (writes to `sv-dev`): T075, a scripted purchase with `pm_card_visa` that ends `paid` with a balanced ledger and two emails in Mailpit, `pm_card_chargeDeclined` releasing the item, and T058 reporting zero double sales; the 5-second browse check (T113) carried over. Prod is read only.
- T058 the double-sell load test (`make loadtest-double-sell ENV=dev`), written here on top of the scripted purchase.
- Memory checkpoint 1 as T032 and T119 did; pull the levers in plan.md if pods' 95th percentile is over 10 GiB.
- `sprint3_retro.md`, the verification-log rows, the handoff and the lab map.

Acceptance Criteria Verification:
- `verify_sprint3.sh` passes from the workstation and in the Jenkins verify stage; memory recorded against the projection.

4. Sprint Verification

Run `sprints/sprint-3/verify_sprint3.sh` from the workstation with the lab up for every check. Jenkins runs it with `MINI=local` at the end of every `infra-terraform` build once it is on `main`, reading only. From the workstation it makes scripted purchases in `sv-dev` with Stripe test cards and the T058 load test; it never writes to prod. Quickstart step 3 is run once by hand.

5. Out of Scope for Sprint 3

Everything in Sprint 4 (section 6): the rebuild drill with restore, the blocked-release and rollback demonstrations and image signing, the trace continuity test, change events, dashboards and SLOs, the traffic generator and synthetic users, the log shipper, the template's GitOps output and the `hello` service, and the Gate 1 release work. Also T124's Drain3 analysis (after Sprint 4) and Tailscale.

6. Sprint 4 Outline (Nov 27 – Dec 10, 2026): Operate It, Then Gate 1

To be written as `sprints/sprint-4/sprint4.md` when Sprint 3 closes. Order matters: each ticket builds on the one before.

| Ticket | Tasks | Why in this order |
| --- | --- | --- |
| 4.1 Rebuild from Git | T076–T079, T110 | the riskiest operational change, first, while everything else is stable |
| 4.2 Traffic | T088–T091 (T090 extends `services/seed`) | everything after it needs traffic; memory checkpoint 2 |
| 4.3 Logs | T125 | the shipper, spiked with traffic running; memory checkpoint 3 |
| 4.4 Follow one purchase | T084–T087, T114, T123 | trace test, change events, dashboards, SLOs, with real traffic to show |
| 4.5 Safe releases | T081, T082, T122 | blocked CVE release, timed rollback, signed images |
| 4.6 New service from the template | T092, T093 | timed against SC-009 |
| 4.7 Gate 1 | T094–T102, T121 (T100 as `verify_sprint4.sh`) | SC-001 to SC-010 where automatable, ADRs, case study, final README |
