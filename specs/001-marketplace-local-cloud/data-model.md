# Data Model: Sorted Vintage Marketplace on the Local Cloud

**Feature**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md) · **Research**: [research.md](./research.md)

Each service owns its own database inside its environment's CloudNativePG cluster. No service reads another's tables; cross-service references are IDs only. Money is integer cents in USD. Times are UTC `timestamptz`. IDs are UUIDv7 unless noted.

| Owner | Entities |
| --- | --- |
| Keycloak (realm per environment) | Account |
| Listings | Seller profile, Listing, Photo, Reservation |
| Orders | Order, Outbox message |
| Payments | Connected account, Payment event, Ledger entry |
| Notifications | Notification |
| Observability stack | Change event |

---

## Account (Keycloak)

The identity record. Services know an account only by its Keycloak subject (`sub`).

| Field | Type | Rules |
| --- | --- | --- |
| sub | UUID | Keycloak user ID; the account's identity everywhere else |
| email | string | Unique within the realm; verified by a Mailpit link (FR-001) |
| display_name | string | 1–40 characters; stored as a user attribute and issued as a token claim |
| created_at | timestamp | Set by Keycloak |

There is one account type: any account can buy and sell (FR-002).

**Storage**: Keycloak's own CloudNativePG `Cluster`, `keycloak-db`, archived and restored with the service databases, so accounts survive stop and start (FR-024) and the rebuild drill (FR-023; [research R16](./research.md#r16-keycloaks-database)).

## Seller profile (Listings)

Created the first time an account starts a listing.

| Field | Type | Rules |
| --- | --- | --- |
| account_sub | UUID | Primary key |
| display_name | string | Copied from the token on each write so profiles show current names |
| sold_count | integer | Incremented when a listing becomes `sold` |
| created_at | timestamp | |

Payout status is not stored here. Listings asks Payments for it before publishing (see Connected account), so there is one source of truth.

## Listing (Listings)

| Field | Type | Rules |
| --- | --- | --- |
| id | UUID | |
| seller_sub | UUID | References Seller profile |
| title | string | 3–80 characters |
| brand | string | 1–40 characters; indexed for exact filtering |
| category | enum | `tops`, `bottoms`, `dresses`, `outerwear`, `shoes`, `accessories` |
| size | string | 1–10 characters, from a per-category list |
| condition | enum | `new_with_tags`, `like_new`, `good`, `fair` |
| price_cents | integer | 100–1,000,000 (from $1 to $10,000) |
| description | text | 0–2,000 characters |
| status | enum | `draft`, `available`, `reserved`, `sold`, `deleted` |
| version | integer | Optimistic lock for edits |
| search_vector | tsvector | Generated from title, brand and description (FR-007) |
| created_at, published_at, updated_at | timestamp | Browse orders by `published_at` descending |

**Validation**: publishing requires 1–8 photos with `state = stored` and a seller whose payout status is `ready` (FR-004, FR-014). Edits and deletes are refused while `status = reserved` (edge case) and are not allowed once `sold`.

**States** (FR-006 names the public states `available`, `reserved` and `sold`; `draft` and `deleted` are internal):

```text
draft ──publish──▶ available ──reserve──▶ reserved ──confirm sale──▶ sold
  │                  │  ▲                    │
  │                  │  └──────release───────┘   (expiry, payment failed, cancelled)
  └──delete──▶ deleted ◀──delete──┘
```

- `available → reserved` is the conditional update in [research R8](./research.md#r8-checkout-consistency-across-services); it is the only way to reserve.
- `reserved → sold` requires the reservation for the same order to be `active`.

## Photo (Listings)

| Field | Type | Rules |
| --- | --- | --- |
| id | UUID | |
| listing_id | UUID | References Listing |
| storage_key | string | MinIO key `listings/<listing_id>/<photo_id>` |
| content_type | enum | `image/jpeg`, `image/png`, `image/webp`; checked from file bytes, not the file name (FR-005) |
| size_bytes | integer | At most 10,485,760 |
| position | integer | 0–7; unique per listing |
| state | enum | `pending`, `stored` |

**Interrupted upload**: the row is created as `pending`, the object is written, and only then does the row become `stored`. Publishing ignores `pending` photos, and a cleanup job deletes `pending` rows and their objects after one hour. A listing therefore never references a missing photo.

## Reservation (Listings)

| Field | Type | Rules |
| --- | --- | --- |
| id | UUID | |
| listing_id | UUID | Partial unique index on `listing_id` where `state = active` (at most one active hold per item) |
| buyer_sub | UUID | Must differ from the listing's `seller_sub` (User Story 2, scenario 4) |
| order_id | UUID | The order this hold belongs to |
| expires_at | timestamp | `created_at + 10 minutes` (FR-009) |
| state | enum | `active`, `released`, `consumed` |

```text
active ──sale confirmed──▶ consumed
   └──expired / payment failed / cancelled──▶ released   (listing returns to available)
```

## Order (Orders)

| Field | Type | Rules |
| --- | --- | --- |
| id | UUID | Shown to the buyer; the lookup key for traces (User Story 5) |
| listing_id | UUID | |
| buyer_sub, seller_sub | UUID | |
| amount_cents | integer | The listing price when checkout started (FR-013) |
| fee_pct | numeric(5,2) | The platform fee setting when checkout started (default 10.00) |
| payment_intent_id | string | Unique; set when Payments creates the PaymentIntent |
| status | enum | `pending`, `paid`, `failed`, `refunded` |
| failure_reason | string | Set for `failed` and `refunded` |
| created_at, paid_at, closed_at | timestamp | |

**States** (FR-011: each transition is accepted at most once, and events that do not apply to the current state are ignored):

```text
pending ──payment succeeded, reservation consumed──▶ paid
pending ──payment failed / reservation expired / provider unreachable──▶ failed
pending ──payment succeeded after the reservation was released──▶ refunded
```

`paid`, `failed` and `refunded` are final. An event that arrives for a final order is recorded and ignored, which makes repeated or out-of-order events harmless.

## Outbox message (Orders)

| Field | Type | Rules |
| --- | --- | --- |
| id | UUID | Becomes the message's `event_id` |
| event_type | string | See [contracts/orders-events.asyncapi.yaml](./contracts/orders-events.asyncapi.yaml) |
| payload | jsonb | The message body |
| traceparent | string | W3C trace context saved at write time ([research R9](./research.md#r9-trace-context-over-rabbitmq)) |
| created_at, published_at | timestamp | `published_at` null until the relay gets a publisher confirm |

Written in the same transaction as the Order change it describes.

## Connected account (Payments)

| Field | Type | Rules |
| --- | --- | --- |
| account_sub | UUID | Primary key |
| stripe_account_id | string | Unique; `acct_…` in this environment's Stripe sandbox |
| details_submitted, charges_enabled, payouts_enabled | boolean | Updated from `account.updated` and the reconciliation loop |
| payout_status | derived | `ready` when `charges_enabled` and `payouts_enabled`; `pending` when the account exists; `none` when there is no row |
| updated_at | timestamp | |

## Payment event (Payments)

The inbox. Each Stripe event is stored once.

| Field | Type | Rules |
| --- | --- | --- |
| stripe_event_id | string | Primary key (`evt_…`); a duplicate insert is a no-op (FR-011) |
| type | string | For example `payment_intent.succeeded` |
| source | enum | `webhook`, `connect_webhook`, `reconciliation` |
| payment_intent_id | string | Null for account events |
| payload | jsonb | The verified event body |
| received_at | timestamp | |
| applied_at | timestamp | Null until it has been applied to Orders; the worker retries until it is set |

Events from reconciliation have no Stripe event ID, so they use `recon:<payment_intent_id>:<status>` as the key, which also deduplicates against itself.

## Ledger entry (Payments)

| Field | Type | Rules |
| --- | --- | --- |
| id | UUID | |
| order_id | UUID | |
| party | enum | `platform`, `seller` |
| account_sub | UUID | Null for `platform` |
| amount_cents | integer | Positive for a credit, negative for a refund reversal |
| kind | enum | `sale`, `refund` |
| created_at | timestamp | |

**Rule**: for each order and `kind = sale`, exactly one `platform` and one `seller` entry, with `platform = round_half_up(amount × fee_pct / 100)` and `seller = amount − platform` ([research R7](./research.md#r7-money-arithmetic-and-the-ledger)). A unique index on `(order_id, party, kind)` enforces this. A refund adds the matching negative pair, so the entries for a refunded order sum to zero.

## Notification (Notifications)

| Field | Type | Rules |
| --- | --- | --- |
| id | UUID | |
| event_id | UUID | The source message's `event_id`; unique with `template`, so a redelivered message sends nothing new |
| template | enum | `order_confirmation_buyer`, `item_sold_seller` (FR-015) |
| recipient_sub | UUID | The address is looked up from Keycloak at send time |
| attempts | integer | At most 5 |
| state | enum | `queued`, `sent`, `dead_lettered` |
| last_error | string | |
| created_at, sent_at | timestamp | |

After the fifth failed delivery the message goes to the dead-letter queue and the row becomes `dead_lettered` (FR-017).

## Change event (observability stack)

Not stored in a service database ([research R11](./research.md#r11-change-events-fr-021)).

| Field | Source |
| --- | --- |
| service | Argo CD Application name |
| version | Image tag from the synced revision |
| env | `dev` or `prod` |
| revision | GitOps commit SHA |
| time | Sync finish time |

Stored as a Grafana annotation and as a JSON log line in Loki.
