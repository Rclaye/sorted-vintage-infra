# Feature Specification: Sorted Vintage Marketplace on the Local Cloud

**Feature Branch**: `001-marketplace-local-cloud`
**Created**: 2026-10-29
**Status**: Draft
**Input**: Project 1 of the Sorted Vintage program. A peer-to-peer resale marketplace where anyone can sign up, list their own clothes and get paid by buyers on the site, running on a local platform that rebuilds from Git and emits the signals the later AIOps projects depend on.

## Clarifications

### Session 2026-10-29

- Q: How do sellers get paid in v1? → A: Stripe Connect Express in test mode. Sellers onboard a connected account before their first listing goes live; each payment carries the platform fee and routes the remainder to the seller.
- Q: Are offers and counter-offers in v1? → A: No. Buy-now at asking price only; offers are a post-Gate 5 case study.
- Q: Frontend approach? → A: Server-rendered pages from the BFF (Jinja templates with HTMX). Recorded here as a plan input.
- Q: How are dev and prod separated? → A: Two namespaces in one Kind cluster, each with its own data stores. Recorded here as a plan input.
- Q: How should new services and environments be added? → A: Environments are generated from the GitOps repo's folder layout; a new service starts from a template and needs one pull request.
- Q: Does the lab run continuously? → A: No. It runs in working sessions; the Mac mini is on while I work and off otherwise. Telemetry and data must survive between sessions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Seller signs up and lists an item (Priority: P1)

A visitor creates an account, becomes a seller and publishes a listing for one piece of clothing with a title, brand, size, condition, price and photos. The listing appears in browse and search results.

**Why this priority**: without listings there is nothing to buy and no traffic for any later project.

**Independent Test**: on a fresh environment, a new account completes test-mode payout onboarding and publishes a listing with two photos, and a second, signed-out visitor finds it by searching the brand.

**Acceptance Scenarios**:

1. **Given** a visitor with no account, **When** they sign up with an email and password, **Then** they can sign in and reach a "Sell an item" page.
2. **Given** a new seller, **When** they first try to publish, **Then** they are sent through payout onboarding, and the listing publishes once onboarding is complete.
3. **Given** a signed-in seller, **When** they submit a listing with all required fields and 1–8 photos, **Then** the listing is visible in browse within 5 seconds.
4. **Given** a published listing, **When** any visitor searches by brand, title words or size, **Then** the listing appears in the results.
5. **Given** a seller, **When** they upload a file that is not an image or exceeds the size limit, **Then** the upload is rejected with a clear message and nothing is stored.

---

### User Story 2 - Buyer purchases an item and the seller is notified (Priority: P1)

A signed-in buyer buys an available listing at its asking price, pays in Stripe test mode, and sees an order confirmation. The item is marked sold and the seller receives an email.

**Why this priority**: the purchase path is the synchronous chain whose failures drive the Failure Lab.

**Independent Test**: buy one listing with a Stripe test card; the order shows as paid, the listing shows as sold, and the seller's email appears in the local mail catcher.

**Acceptance Scenarios**:

1. **Given** an available listing, **When** a buyer starts checkout, **Then** the item is reserved for that buyer and shown as unavailable to others.
2. **Given** a reserved item, **When** payment succeeds, **Then** the order becomes paid, the listing becomes sold and the seller is emailed.
3. **Given** a reserved item, **When** payment fails or is abandoned, **Then** the reservation is released and the item is available again.
4. **Given** a buyer, **When** they try to buy their own listing, **Then** checkout is refused.
5. **Given** the payment amount, **When** the order is paid, **Then** the platform fee and the seller's share are recorded as ledger entries that sum to the amount paid.

---

### User Story 3 - Operator rebuilds the platform from Git (Priority: P1)

The platform engineer destroys the lab environment and rebuilds it, with the marketplace and its data stores, from the repositories with one command.

**Why this priority**: Principle II; it is also the first case-study metric.

**Independent Test**: on the Mac mini, destroy everything, run the one documented command (`make rebuild`), and time how long it takes until every application reports healthy and a purchase succeeds.

**Acceptance Scenarios**:

1. **Given** an empty machine with only prerequisite tools installed, **When** the operator runs the documented single command, **Then** all platform components and services reach healthy without manual steps.
2. **Given** a rebuilt environment, **When** the seed job runs, **Then** demo sellers, listings and photos exist.

---

### User Story 4 - Operator ships a change to prod through review (Priority: P2)

A code change to any service is built, scanned and deployed to dev automatically, then promoted to prod only through an approved pull request.

**Why this priority**: Principles I and III; it is the delivery path every later project uses.

**Independent Test**: change a response field in one service; observe it in dev without any manual step, then in prod only after a pull request is approved and merged.

**Acceptance Scenarios**:

1. **Given** a merged code change, **When** CI passes, **Then** the new image version is running in dev without anyone touching the cluster.
2. **Given** a version running in dev, **When** a promotion pull request is approved and merged, **Then** prod runs that version.
3. **Given** a scan finding of critical severity, **When** CI runs, **Then** the image is not published and nothing is deployed.
4. **Given** a bad release in prod, **When** the promotion commit is reverted, **Then** prod returns to the previous version.

---

### User Story 5 - Operator follows one purchase across every service (Priority: P2)

From a single order ID, the operator finds the request's full trace, its logs and the metrics of every service it touched, including the asynchronous email step.

**Why this priority**: Principle V; the investigator in Project 4 needs this to work.

**Independent Test**: complete one purchase, look up its trace by order ID and confirm it spans every service involved, with linked logs.

**Acceptance Scenarios**:

1. **Given** a completed purchase, **When** the operator searches by order ID, **Then** one trace shows every synchronous hop and the queued notification step.
2. **Given** any log line produced during that purchase, **When** the operator opens it, **Then** it carries the trace ID.
3. **Given** a deployment, **When** it is synced, **Then** a change event with the service, version and time is recorded alongside the telemetry.

---

### User Story 6 - The platform has realistic traffic whenever it runs (Priority: P2)

A traffic generator starts with the platform and browses, searches, lists and buys at a configurable rate for the whole session, so dashboards and baselines reflect steady use rather than an idle system.

**Why this priority**: anomaly detection in Project 3 needs many hours of normal behaviour to learn from, accumulated across sessions.

**Independent Test**: run a 4-hour session; every service shows request rates throughout and the order count has grown.

**Acceptance Scenarios**:

1. **Given** the platform has started, **When** a session runs, **Then** every service has non-zero traffic in every 5-minute window.
2. **Given** a configured rate curve (a full daily-shaped cycle compressed into 2 hours by default), **When** traffic runs, **Then** request rates rise and fall on that cycle.
3. **Given** generated purchases, **When** they complete, **Then** they use Stripe test mode and synthetic users only.

---

### User Story 7 - Operator adds a new service from the template (Priority: P3)

The platform engineer creates a new service from the service template, opens one pull request, and the service appears in dev with health checks, metrics, traces and dashboards already wired, and in prod once promoted.

**Why this priority**: it shows the platform serves developers, not just one app; the full self-service portal is deferred to Project 6.

**Independent Test**: generate a "hello" service from the template, merge one pull request, and see it healthy in dev with a dashboard, without editing any platform configuration.

**Acceptance Scenarios**:

1. **Given** the template, **When** a new service is generated, **Then** it already meets Principle V and the security policies.
2. **Given** the new service's folder is merged into the GitOps repo, **When** Argo CD syncs, **Then** dev and prod environments for it exist with no other change.
3. **Given** a manifest that runs as root or has no resource limits, **When** it reaches the cluster by any route, **Then** it is rejected.

---

### Edge Cases

- Two buyers start checkout for the same item within the same second: exactly one gets the reservation.
- The payment provider sends the same webhook twice, or out of order: the order is processed once and ends in the correct state.
- Payment succeeds after the reservation has expired: the payment is refunded automatically or the order is flagged for review, never sold twice.
- The seller edits or deletes a listing while it is reserved: the change is refused until the reservation ends.
- The email service is down when a sale completes: the sale still completes and the email is sent after recovery.
- The payment provider is unreachable: checkout fails cleanly, the reservation is released, and no order is left half-paid.
- A photo upload is interrupted: no listing references a missing photo.
- A service restarts mid-checkout: the order resumes or rolls back to a consistent state.

## Requirements *(mandatory)*

### Functional Requirements

**Accounts**
- **FR-001**: Users MUST be able to sign up, sign in and sign out with email and password.
- **FR-002**: Any signed-in user MUST be able to sell and buy; there is one account type.
- **FR-003**: Every service MUST reject requests without a valid, unexpired session token.

**Listings**
- **FR-004**: Sellers MUST be able to create, edit and delete listings with title, brand, category, size, condition, price, description and 1–8 photos.
- **FR-005**: Photos MUST be limited to JPEG, PNG or WebP files of at most 10 MB each.
- **FR-006**: Each listing represents exactly one item, with status available, reserved or sold.
- **FR-007**: Visitors MUST be able to browse newest-first and search by text, brand, size and price range without signing in.
- **FR-008**: Each seller MUST have a public profile showing their available and sold listings.

**Checkout and payments**
- **FR-009**: Starting checkout MUST reserve the item for 10 minutes; an item MUST never be reserved by, or sold to, more than one buyer.
- **FR-010**: Buyers MUST pay through Stripe in test mode; the system MUST NOT store card data.
- **FR-011**: Payment confirmation MUST be idempotent: repeated or out-of-order provider events produce exactly one final order state.
- **FR-012**: Each paid order MUST produce ledger entries for the platform fee and the seller's share. The platform fee is a configurable percentage, defaulting to 10%.
- **FR-013**: Purchases MUST be at the asking price; offers and counter-offers are out of scope for v1.
- **FR-014**: Sellers MUST complete Stripe Connect Express onboarding in test mode before a listing can be published; each payment MUST deduct the platform fee and route the seller's share to their connected account.

**Notifications**
- **FR-015**: The seller MUST be emailed when their item sells, and the buyer MUST be emailed an order confirmation.
- **FR-016**: Notifications MUST be delivered asynchronously, so a notification outage never blocks or fails a purchase.
- **FR-017**: Messages that repeatedly fail MUST be set aside for inspection rather than retried forever.

**Operations**
- **FR-018**: The whole environment, including seed data, MUST be created from the repositories with one documented command.
- **FR-019**: Dev and prod MUST be isolated environments with independent data.
- **FR-020**: Every service MUST meet Principle V: health and metrics endpoints, structured logs carrying trace IDs, and trace propagation across HTTP and queue hops.
- **FR-021**: Each deployment MUST record a change event with service, version, environment and time.
- **FR-022**: A synthetic traffic generator MUST start with the platform and run at a configurable rate on a repeating, daily-shaped cycle whose length is configurable.
- **FR-023**: Data stores MUST be backed up when a session ends, and a restore MUST be demonstrated during the rebuild drill.
- **FR-025**: Environments for a service MUST be generated from the GitOps repo's folder layout; adding a service MUST need no change to platform configuration.
- **FR-026**: A service template MUST produce a service that meets FR-020 and FR-027 from its first commit.
- **FR-027**: The cluster MUST reject workloads that run as root, lack resource requests and limits, or, for application workloads in dev and prod, use images from outside the project's registry (`ghcr.io/rclaye/`), however they arrive; third-party platform components are exempt from the registry rule; the same rules MUST run in CI on every pull request.
- **FR-024**: Starting and stopping the lab MUST each be one command. After a stop and start, the platform MUST return to healthy with its data and telemetry history intact.

### Key Entities

- **Account**: a person using the site; email, display name, created date.
- **Seller profile**: the public face of an account that sells; listings, sold count, payout account status.
- **Listing**: one item; title, brand, category, size, condition, price, description, photos, status, seller.
- **Photo**: an image belonging to a listing; storage key, type, size, order.
- **Reservation**: a time-limited hold of one listing by one buyer.
- **Order**: a purchase of one listing by one buyer; amount, status (pending, paid, failed, refunded), timestamps.
- **Payment event**: a provider event applied to an order, recorded once.
- **Ledger entry**: an amount credited to the platform or a seller for an order.
- **Notification**: a message to send, with attempts and final state.
- **Change event**: a deployment record used to correlate incidents with releases.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A seller who has completed payout onboarding publishes a listing with photos in under 2 minutes; onboarding itself takes under 5 minutes with Stripe test data.
- **SC-002**: With the traffic generator at its baseline rate, 95% of checkouts complete in under 2 seconds, excluding time spent on the payment page.
- **SC-003**: In a test of 1,000 simultaneous purchase attempts across 100 items, zero items are sold twice.
- **SC-004**: An empty Mac mini reaches a working purchase in under 30 minutes from one command.
- **SC-005**: 100% of sampled purchases have one trace that covers every service involved.
- **SC-006**: Over the project, zero changes reach prod outside an approved pull request, as checked by drift detection.
- **SC-007**: With notifications stopped for 30 minutes, every sale completes, and every queued email is delivered within 5 minutes of recovery.
- **SC-009**: A new service goes from template to healthy in dev in under 30 minutes, with one pull request and no platform change.
- **SC-010**: 100% of test manifests that break policy are rejected both in CI and at admission.
- **SC-008**: From a powered-on mini, the start command brings the platform to healthy in under 10 minutes, with the previous session's orders and dashboards still present.

## Assumptions

- Users are synthetic or the developer; no real personal data is collected.
- The lab runs in working sessions, not continuously.
- Shipping, returns, disputes, offers, messaging between users, ratings and moderation are out of scope for v1.
- One currency (USD) and one country.
- The local mail catcher stands in for real email delivery.
- "Dev" and "prod" are lab environments; prod means the promoted, protected environment, not public internet traffic.
