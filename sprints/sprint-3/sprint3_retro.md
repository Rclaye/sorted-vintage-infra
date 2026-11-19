# Sprint 3 Retrospective: A Buyer Purchases

Sprint 3 ran from 2026-11-12 to 2026-11-18 (planned to 2026-11-26) and closed with User Story 2 working in dev and checked by script: a buyer pays for an item, it is sold exactly once, the seller is paid in the ledger and both are emailed. Eight tickets; 24 tasks (T053–T075, T083), so Project 1 stands at 93 of 125.

## What Was Built

| Ticket | What | Where |
| --- | --- | --- |
| 3.1 | Spikes: destination charge and refund, `stripe trigger`, the Payment Element under the BFF's CSP, the RabbitMQ topology, the Notifications Keycloak client | infra #51 |
| 3.2 | 53 contract tests written first as strict xfails; Orders and Notifications from the template | app #18 |
| 3.3 | Listings reservations (10-minute holds), consume, release and the sweeper | app #19 |
| 3.4 | Orders: checkout, payment results, expiry that releases, cancels and waits, the outbox relay; the T070 topology | app #20, gitops #58 |
| 3.5 | Payments: charges, the payment webhook, the inbox worker, the ledger and refunds, reconciliation; the forwarder forwards `canceled` | app #21, gitops #59–#61 |
| 3.6 | Notifications: one email per event and template, dead-letter after five failures; its view-users Keycloak client | app #22–#24, infra #55, gitops #62 |
| 3.7 | The manifests (each service its own RabbitMQ user), BFF checkout, `order_id` on spans, logs and baggage in every service | gitops #63, app #25, #26 |
| 3.8 | `verify_sprint3.sh`, the scripted purchase and decline, T058 double-sell test, the verify buyer, memory checkpoint 1 | infra #58 and the closing PR; gitops #70; app #27 and the load-test PR |

## Verification

- **`verify_sprint3.sh` passes in both modes** (2026-11-18): from the workstation in 2 min 14 s, with the purchase, the decline, a dead letter and T058; on the lab host with `MINI=local` (the Jenkins verify stage) reading only.
- **Quickstart step 3 by hand** (Ticket 3.7, in the built-in browser pane): a paid purchase with both emails, and a declined card that put the item back on sale.
- **T058, SC-003:** 1,000 simultaneous checkout attempts on 100 fresh items, twice: exactly one payment page per item, the other 900 refused `not_available`, no errors, 100 items sold once, none twice.
- Details and evidence per check are in [docs/verification-log.md](../../docs/verification-log.md).

## Memory: Checkpoint 1

Measured on 2026-11-18 after the load tests, with all 39 Argo CD apps Synced and Healthy, the same way as T032 and T119 (container working sets from Prometheus, through the API server proxy).

| | Sprint 2 (2026-11-12) | Sprint 3 (2026-11-18) |
| --- | --- | --- |
| Pods, now | 8.29 GiB | 8.23 GiB |
| Pods, 24-hour median / 95th percentile | 7.96 / 8.37 GiB | 8.18 / 8.56 GiB |
| Pods, 24-hour peak | 8.81 GiB | 8.80 GiB (during the load tests) |
| Node container, `docker stats` | 9.28 of 11.91 GiB | 9.17 of 11.91 GiB |
| Lab host memory free | 55% | 56% |

By namespace now: monitoring 2.10 GiB, kube-system 1.78, sv-dev 1.27, sv-prod 0.94, Argo CD 0.84, Keycloak 0.74, everything else under 0.2 each. Per service in sv-dev: Listings 457 MiB, Payments 103, Orders 100, Notifications 94, BFF 80, the forwarder's two sessions 86. Prod runs Orders and Notifications at 0 replicas until promoted.

- **The 95th percentile is 8.56 GiB, under the 10 GiB trigger** in plan.md: no lever pulled.
- Orders and Notifications cost about 0.2 GiB together in dev, less than the 0.5 GiB guessed in Sprint 2. Promoting them to prod adds about the same.
- Listings is still the biggest service; a fixed heap in prod stays the first lever. Measure again after the traffic generator and the log shipper (Sprint 4).

## What Went Well

- **Contract tests first paid off.** The 53 strict xfails of Ticket 3.2 told each later ticket exactly when it was done, and none of the services needed its contract changed afterwards (one template, `order_refund_buyer`, was added to the data model to match the contract).
- **Spikes before the lab, again.** The Payment Element CSP, the topology's delivery limit and the per-service RabbitMQ permissions all worked first time in the lab because each was tried on a throwaway cluster or container first.
- **The checks found real problems.** A buyer's `baggage` header could have put anything into logs (now only a UUID is taken); `opentelemetry-api` and `-context` were at different versions until the Spring-managed version was used; the forwarder was not forwarding `canceled`; prod's `/webhooks/stripe` is honestly absent until Payments is promoted.

## What Did Not

- **An intermittent CI hang cost two cancelled builds.** aio-pika's robust connection left reconnect tasks that held the event loop open at shutdown. `faulthandler_timeout` found it the second time; the consumer now reconnects on a plain connection (app #24). Keep `faulthandler_timeout` in every Python service.
- **Three SonarCloud projects were created private, on `master` and unbound** (sv-orders, sv-notifications, sv-seed). Each one failed Jenkins verify, or would have, until fixed by hand. A PR check named plain `SonarCloud Code Analysis`, without `[sv-name]`, is the early sign.
- **Hook-only changes do not sync.** The seed job is an Argo CD PostSync hook, so a new seed image alone left `seed-dev` Synced and the job did not run until a sync was requested.
- **Test purchases sold seeded listings,** which broke Sprint 2's "50 seeded listings in search". The check now counts sold ones from the sellers' pages, and scripted purchases use their own items.

## Carried Into Sprint 4

- **Orders' expiry cancelling a PaymentIntent through Payments' cancel route** has not happened live: it needs an order left unpaid for 10 minutes. It is covered by tests (Tickets 3.4, 3.5); the traffic generator (Ticket 4.2) will leave holds unpaid and show it.
- **The five-failure dead-letter path** (a send failing five times, the row `dead_lettered`) is checked in tests against RabbitMQ 4.3.4; live, a malformed event dead-letters on the spot.
- **Promote** the BFF, Payments, Orders and Notifications to prod with approval when wanted; prod is read only in the verify scripts until then.
- **A small BFF follow-up:** Stripe appends `payment_intent_client_secret` to the return URL; the BFF does not log it, but the order page could redirect once to a clean address.
- **Each T058 run leaves 100 sold test items** with the verify seller (and each purchase check one). They are harmless; a cleanup can come with the traffic generator.
