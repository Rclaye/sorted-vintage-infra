# Contracts

Interfaces between the services of [spec.md](../spec.md). Field rules and state machines live in [data-model.md](../data-model.md) and are not repeated here.

| File | Interface | Callers |
| --- | --- | --- |
| [listings.openapi.yaml](./listings.openapi.yaml) | Listings HTTP API | BFF, Orders |
| [orders.openapi.yaml](./orders.openapi.yaml) | Orders HTTP API | BFF, Payments worker |
| [payments.openapi.yaml](./payments.openapi.yaml) | Payments HTTP API and Stripe webhooks | BFF, Orders, Listings, Stripe CLI forwarder |
| [orders-events.asyncapi.yaml](./orders-events.asyncapi.yaml) | `orders` topic exchange | Orders publishes; Notifications consumes |
| [bff-pages.md](./bff-pages.md) | Browser routes served by the BFF | People and the traffic generator |

## Rules every service follows

These come from Principle V and FR-003, FR-020 and FR-027. The service template (FR-026) produces them, so they are listed once here rather than in each OpenAPI file.

- `GET /healthz` returns 200 with `{"status":"ok"}` when the service can reach its own dependencies (database, queue), and 503 otherwise. It needs no token.
- `GET /metrics` serves Prometheus text format, including `http_server_request_duration_seconds` histograms labelled by route and status. It needs no token and is not exposed through ingress.
- Every other route requires `Authorization: Bearer <Keycloak JWT>` with the service's audience; requests without a valid, unexpired token get 401 (FR-003). The only exceptions are the two Stripe webhook routes in Payments, which require a valid `Stripe-Signature` header instead.
- Every request and message carries W3C `traceparent`; services continue the incoming trace and pass it on.
- Errors use one body shape: `{"error": "<machine_code>", "message": "<human text>"}`.
- Logs are JSON lines with `timestamp`, `level`, `service`, `env`, `trace_id`, `span_id` and `message`.

## Checkout sequence

```text
BFF ──POST /orders──────────────────▶ Orders
                                        ├─POST /listings/{id}/reservations──▶ Listings   (409 if not available)
                                        └─POST /payment-intents─────────────▶ Payments ──▶ Stripe
BFF ◀── order_id, client_secret ───────┘
Browser confirms the PaymentIntent with the Payment Element
Stripe ──▶ stripe listen ──▶ POST /webhooks/stripe ──▶ Payments (store event, 200)
Payments worker ──POST /orders/{id}/payment-result──▶ Orders
                                        ├─POST /reservations/{id}/consume──▶ Listings   (listing → sold)
                                        └─outbox ──▶ exchange "orders" (order.paid) ──▶ Notifications ──▶ Mailpit
```
