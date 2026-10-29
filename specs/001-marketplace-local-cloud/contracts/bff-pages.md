# BFF Pages

The BFF serves server-rendered Jinja pages with HTMX (Clarification 2026-10-29). It holds the OIDC session in an HTTP-only, `Secure`, `SameSite=Lax` cookie and calls the services with the user's access token. Every form that changes state carries a CSRF token. Host: `dev.sortedvtg.lan` or `prod.sortedvtg.lan`.

| Route | Sign-in | Purpose | Spec |
| --- | --- | --- | --- |
| `GET /` | No | Browse newest listings, with search and filters | FR-007 |
| `GET /search?q=&brand=&size=&min=&max=` | No | Search results (HTMX partial when requested by HTMX) | FR-007 |
| `GET /items/{listing_id}` | No | Listing detail with photos and Buy button | US1, US2 |
| `GET /sellers/{account_sub}` | No | Public seller profile | FR-008 |
| `GET /login`, `GET /auth/callback`, `POST /logout` | – | Keycloak code flow with PKCE; sign-up uses Keycloak's registration page | FR-001 |
| `GET /sell` | Yes | "Sell an item": draft form and the caller's listings | US1 |
| `POST /sell/listings` and `POST /sell/listings/{id}/photos` | Yes | Create a draft and upload photos | FR-004, FR-005 |
| `POST /sell/listings/{id}/publish` | Yes | Publish, or redirect to onboarding when payout status is not ready | FR-014 |
| `GET /sell/onboarding` | Yes | Redirect to a fresh Stripe Account Link; also the link's `return_url` and `refresh_url` | FR-014, research R6 |
| `POST /checkout/{listing_id}` | Yes | Start checkout (generates the `Idempotency-Key`) and show the payment page | FR-009 |
| `GET /orders/{order_id}` | Yes | Order status page; polls with HTMX until the order is final | US2 |
| `GET /orders` | Yes | The caller's orders | US2 |
| `GET /healthz`, `GET /metrics` | No | See [README](./README.md) | FR-020 |

The payment page loads Stripe.js from `js.stripe.com` with the environment's publishable key and confirms the PaymentIntent in the browser. The traffic generator follows the same routes, then confirms the PaymentIntent with a test PaymentMethod ([research R6](../research.md#r6-payment-ui-and-synthetic-purchases)).
