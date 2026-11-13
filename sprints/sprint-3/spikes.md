# Sprint 3 spikes (Ticket 3.1)

Each spike answers one risk before the ticket that depends on it starts ([sprint3.md](./sprint3.md)). Stripe spikes ran in the lab's `sv-dev` against the dev test sandbox; the RabbitMQ and Keycloak spikes ran on a throwaway Kind cluster `sv-spike`, built from the lab's node image while the lab was down (`make down`, then `make up`: all 35 apps Synced and Healthy again after 263 s).

## Destination charge and refund (T066, T068)

**2026-11-12, pass, in the dev sandbox.** A pod in `sv-dev` called the Stripe API with the environment's key (`sk_test_…`, Secret `stripe`):

| Step | Result |
| --- | --- |
| PaymentIntent, $25.00, `application_fee_amount` 250, `transfer_data.destination` `demo-seller-1`, `automatic_payment_methods` with `allow_redirects: never`, `pm_card_visa`, confirmed server-side, the order ID as idempotency key | 200, `succeeded` |
| The charge | `transfer` `tr_…` of the **full** 2500 to the seller; `application_fee` `fee_…` of 250 back to the platform |
| Refund with `reverse_transfer` and `refund_application_fee` | 200, `succeeded`, a transfer reversal `trr_…`; the transfer shows `reversed: true`, 2500; the application fee `refunded: true`, 250 |
| The same with `pm_card_chargeDeclined` | 402 `card_declined` (`generic_decline`); the PaymentIntent stays `requires_payment_method` |
| The forwarder's platform session | delivered `payment_intent.succeeded` and `payment_intent.payment_failed` to `http://payments/webhooks/stripe`, which answered 404 until Ticket 3.5 |

- For the ledger (T068): with a destination charge the seller receives the whole amount as a transfer and the platform's share comes back as an application fee, so `seller = amount − fee` holds on Stripe's side too. A refund with both flags returns all three objects to zero.
- `allow_redirects: never` is needed for a server-side confirm with a test card; the BFF's Payment Element leaves it at the default.
- `charge.transfer` and `charge.application_fee` are ids; `expand[]` as a query list did not expand them through `httpx`'s params. Read them by id.

## Why `stripe trigger` failed (2026-11-12 platform-hygiene spike)

**Explained.** Two separate causes: `--skip-update` is a flag of `listen` only (`trigger` answers "unknown flag"), and the CLI's `payment_intent` fixture still sends `payment_method_types`, which this API version refuses with 400 ("The `payment_method_types` parameter is no longer supported", as T009 found for our own code). So `stripe trigger` cannot create PaymentIntent events in these sandboxes: `verify_sprint3.sh` (T075) creates and confirms PaymentIntents through the API, as the spike above did. The CLI also reported v1.55.11 against the mirrored v1.55.2.

## Payment Element under the BFF's Content-Security-Policy (T073)

**Pass with changes.** A test page served from the workstation with the BFF's exact CSP, then with additions, loaded in a browser; Stripe.js in deferred-intent mode (`mode: payment`, no PaymentIntent created) with dev's publishable key:

| CSP | Result |
| --- | --- |
| The BFF's today (`script-src 'self'`, no `frame-src` or `connect-src`) | Stripe.js does not load |
| Plus `script-src https://js.stripe.com https://*.js.stripe.com`, `frame-src https://js.stripe.com https://*.js.stripe.com https://hooks.stripe.com`, `connect-src 'self' https://api.stripe.com`, `img-src … https://*.stripe.com` | The Payment Element reports `ready`; card number, expiry, CVC, country and ZIP render in Stripe's frames; no CSP refusal in the console |

- `style-src 'self'` can stay: the Element styles itself inside its frames.
- Not yet seen: `confirmPayment` from the page (and any 3-D Secure frame), which needs a real PaymentIntent; Ticket 3.7 checks it by hand.
- The Element also offered Bank, Cash App Pay, Klarna and Link, as the sandbox's payment-method settings allow; the platform can narrow them in the Dashboard if wanted.

## RabbitMQ topology from manifests (T070)

**Pass, on `sv-spike`.** cert-manager v1.21.3, the Cluster Operator v2.23.2 and the Messaging Topology Operator v1.20.5 (the lab's release files), a single-node `RabbitmqCluster` like the lab's (RabbitMQ 4.3.4). The draft of `services/orders/base/messaging.yaml`: topic exchange `orders`, fanout exchange `orders.dlx`, quorum queue `notifications.orders` with arguments `x-delivery-limit: 5` and `x-dead-letter-exchange: orders.dlx`, quorum queue `notifications.orders.dead`, and bindings for `order.paid`, `order.refunded` and the dead-letter exchange.

| Check | Result |
| --- | --- |
| All seven objects | Ready in seconds; `rabbitmqctl` shows the queue types, arguments and bindings as written |
| Publish `order.paid`, `order.refunded`, `order.failed` to `orders` | the first two routed to `notifications.orders`; `order.failed` routed nowhere (not bound) |
| Reject and requeue `order.paid` repeatedly | delivered 6 times (`x-delivery-count` none, then 1 to 5), then dead-lettered into `notifications.orders.dead` with reason `delivery_limit` |

- **For T072:** `x-delivery-limit: 5` allows six deliveries in all. For "reject after the fifth failure", the consumer rejects without requeue on its fifth failure itself (or the limit is 4); the queue limit then only catches a consumer that crashes mid-message.
- The management API's message counts lag a few seconds behind; read the queue, not the count, in tests.

## Keycloak service client for Notifications (T072)

**Pass, on `sv-spike`.** The realm already has service clients for Orders (audiences `payments`, `listings`), Payments (`orders`) and Listings (`payments`), which cover Sprint 3's service-to-service calls. The gap is Notifications, which reads buyers' and sellers' email addresses. Keycloak 26.8.1 as the lab runs it (`start-dev` here, the lab's hostname settings); keycloak-config-cli 6.5.1 applied today's `sv-dev.json`, then the same file with a `notifications` client (confidential, service account only, secret `${SV_DEV_NOTIFICATIONS_SECRET}`) and its service-account user holding `realm-management` `view-users`.

| Check | Result |
| --- | --- |
| config-cli, today's file then the new one, then the new one again | applied each time; the existing `seed` client still creates users (201) |
| `notifications` token (client credentials) | 200; `azp` `notifications`; roles `view-users`, `query-users`, `query-groups` |
| `GET /admin/realms/sv-dev/users/{id}` | 200 with the email |
| `PUT` and `DELETE` that user, `POST` a user, `GET` clients | 403, 403, 403, 403 |

- Terraform must create `SV_DEV_NOTIFICATIONS_SECRET` and `SV_PROD_NOTIFICATIONS_SECRET` (and `notifications` in each environment's `keycloak-clients` Secret) before the realm files refer to them, as for `seed` (infra change first).
