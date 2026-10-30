# Research: Sorted Vintage Marketplace on the Local Cloud

**Feature**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md) · **Date**: 2026-10-29

Phase 0 of `/speckit-plan`. The Technical Context has no open NEEDS CLARIFICATION items; this file settles the integration questions the plan named (Stripe in a lab with no inbound internet, trace context over RabbitMQ, Kind networking on Docker Desktop) and the risks found while checking them. Items marked **Spike** are decided here but must be confirmed by a test in Sprint 1 before the dependent tasks start.

---

## R1. Kind topology and stop/start sessions

- **Decision**: a single-node Kind cluster (one control-plane node that also runs workloads), not one control plane and two workers.
- **Rationale**: FR-024 and SC-008 need the cluster to survive `make down` / `make up`, which stops and starts the node containers. Kind's maintainers describe restart as working for single-node clusters but failing for multi-node clusters when Docker assigns the nodes different IPs on restart ([kind#2715](https://github.com/kubernetes-sigs/kind/issues/2715)); the known workarounds patch the kubeadm config by hand, which Principle II forbids. On one physical host, extra Kind nodes add no real fault isolation, and dropping them saves about 0.3 GB.
- **Alternatives considered**: three nodes with a script that rewrites node IPs after start (manual repair, fragile); three nodes recreated every session (loses PV-backed state unless every volume is an extraMount, and breaks SC-008's 10-minute start); k3d (restart-safe multi-node, but replaces the tool chosen in ADR-0001).
- **Revisit when**: a Failure Lab scenario needs node failure. Re-test multi-node restart on the Kind version in use then.
- **Spike (Sprint 1, T008, before T010)**: create the cluster, deploy a PVC-backed pod, `docker stop`/`docker start` the node, confirm the API server, the pod and its data return.

## R2. Reaching the lab: ingress ports and Principle VI

- **Decision**: Kind `extraPortMappings` for 80 and 443 with `listenAddress: 127.0.0.1` on the mini. The Air reaches `*.sortedvtg.lan` through an SSH local forward (`ssh -L 8443:127.0.0.1:443 mac-mini`) and `/etc/hosts` entries pointing the names at 127.0.0.1. When Tailscale is installed, `listenAddress` moves to the mini's Tailscale IP.
- **Rationale**: Principle VI says the lab is reachable only over the private Tailscale network. Tailscale was deferred in Sprint 0, so binding to all interfaces would expose the marketplace to the whole home network. Binding to loopback keeps SSH (key-only) as the only way in until Tailscale is installed, then switches to it.
- **Alternatives considered**: bind to `0.0.0.0` (exposes the lab on the LAN); install Tailscale first (blocked by the client problems recorded in the Sprint 0 retro).
- **TLS**: mkcert issues a wildcard certificate for `*.sortedvtg.lan`; the mkcert root CA is trusted on the Air only. The certificate and key enter the cluster as a Secret created by Terraform from a git-ignored file (same path as the Stripe keys, T012).

## R3. Stripe: one sandbox per environment

- **Decision**: two Stripe test-mode sandboxes, `sorted-vintage-dev` and `sorted-vintage-prod`, each with its own API keys, Connect settings and `stripe listen` forwarder.
- **Rationale**: a `stripe listen` session receives every event for the account its key belongs to. With one shared test account, the dev and prod forwarders would both receive every payment, and each environment would try to apply the other's events. Separate sandboxes keep payments, connected accounts and events independent, which FR-019 requires.
- **Alternatives considered**: one account with an `environment` value in PaymentIntent metadata that each Payments service checks before ignoring the event (works for payments, but connected accounts and `account.updated` events would still be shared, so a seller onboarded in dev would appear in prod).

## R4. Stripe webhooks without inbound internet

- **Decision**: one `stripe listen` Deployment per namespace, run as `stripe listen --api-key $KEY --forward-to http://payments/webhooks/stripe --forward-connect-to http://payments/webhooks/stripe-connect`. Payments verifies signatures with the CLI's signing secret, which stays the same across restarts of `listen` for the same key ([Stripe CLI listen](https://github.com/stripe/stripe-cli/wiki/listen-command)).
- **Event routing**: with destination charges, `payment_intent.succeeded` and `payment_intent.payment_failed` arrive on the platform stream ([Stripe Connect webhooks](https://docs.stripe.com/connect/webhooks)); `account.updated` for sellers' onboarding status arrives on the Connect stream, which needs `--forward-connect-to`.
- **Spike (Sprint 1)**: confirm that Connect-forwarded events are signed with the same secret as platform events. If they are not, Payments stores two secrets.
- **Rationale**: the CLI makes an outbound connection, so no port is opened (Principle VI).
- **Alternatives considered**: a public tunnel such as ngrok or Cloudflare Tunnel (exposes the lab to the internet); polling Stripe only (adds latency to every sale, though see R5).

## R5. Events missed while the lab is off

- **Decision**: Payments runs a reconciliation loop at startup and every 5 minutes. It lists orders that are `pending` for longer than 2 minutes, retrieves each PaymentIntent from Stripe, and applies the result as if the matching webhook had arrived, through the same idempotent path. The same loop refreshes connected-account status for sellers whose onboarding is incomplete.
- **Rationale**: the lab runs in sessions (Clarification 2026-10-29), and `stripe listen` only forwards events while it is connected, so a payment that finishes as the session ends would otherwise stay pending forever. Reconciliation also covers the edge case "a service restarts mid-checkout".
- **Alternatives considered**: rely on Stripe retries (retries go to registered webhook endpoints, not to a CLI session that is no longer listening); `stripe events resend` at startup (needs the event IDs, which the lab does not have if it missed them).

## R6. Payment UI and synthetic purchases

- **Decision**: PaymentIntents with the Payment Element on a BFF page, not hosted Stripe Checkout. The traffic generator creates the order through the BFF, then confirms the PaymentIntent server-side with Stripe's test payment methods (`pm_card_visa` for success, `pm_card_chargeDeclined` for a share of failures).
- **Rationale**: a headless generator cannot complete a hosted Checkout page; confirming the PaymentIntent with a test PaymentMethod exercises the same webhook, ledger and notification path as a person paying in the browser (User Story 6). Card data never touches the platform (FR-010).
- **Alternatives considered**: Stripe Checkout (simpler page, but the generator would need a browser); a "fake payment" bypass in test builds (skips the real chain the Failure Lab depends on).
- **Onboarding**: Express onboarding uses Account Links with `return_url` and `refresh_url` on `https://<env>.sortedvtg.lan/sell/onboarding`. These are browser redirects, so the lab does not need to be publicly reachable. Test onboarding uses Stripe's published test values (test phone number and verification code, test bank account). **Spike (Sprint 2)**: confirm Stripe accepts a `.lan` redirect host in test mode; if not, use `http://localhost:8443`, which the SSH forward from R2 provides.

## R7. Money arithmetic and the ledger

- **Decision**: all amounts are integer cents. `platform_fee = round_half_up(amount × fee_pct / 100)`, `seller_share = amount − platform_fee`. The PaymentIntent is created with `application_fee_amount = platform_fee` and `transfer_data.destination = seller's connected account`. Two ledger entries are written in the same transaction that marks the order paid.
- **Rationale**: computing the seller's share as the remainder guarantees the entries sum to the amount paid (User Story 2, scenario 5) with no rounding gap, and the fee Stripe applies matches the ledger exactly.
- **Alternatives considered**: separate charges and transfers (more moving parts; destination charges were chosen in the plan); floating-point percentages (rounding drift).

## R8. Checkout consistency across services

- **Decision**:
  - **Reservation**: Listings performs `UPDATE listing SET status='reserved' … WHERE id=? AND status='available'` and inserts a reservation row in the same transaction. Zero rows updated means the item is taken. A sweeper releases reservations past `expires_at` (10 minutes, FR-009).
  - **Inbox in Payments**: the webhook handler verifies the signature, inserts the event (unique on Stripe event ID) and returns 200 at once. A worker applies stored events to Orders with retries, so an Orders outage never loses an event.
  - **Outbox in Orders**: the order state change and an outbox row are written in one transaction; a relay publishes outbox rows to RabbitMQ with publisher confirms. Notifications consumers are idempotent on `event_id`.
  - **Late success**: if a PaymentIntent succeeds after its reservation expired and the listing is no longer reserved for that buyer, Orders marks the order `refunded`, and Payments issues a refund that reverses the transfer and the application fee.
  - **Cancellation**: when a reservation is released for a pending order, Payments cancels the PaymentIntent so a late confirmation cannot succeed. The late-success rule above covers the race where confirmation wins.
- **Rationale**: the conditional update makes the database the single arbiter of item state (SC-003); the inbox and outbox remove the dual-write failures behind the "service restarts mid-checkout" edge case.
- **Alternatives considered**: distributed locks in Redis (another component on a tight memory budget); a saga orchestrator such as Temporal (too heavy for Principle VII).

## R9. Trace context over RabbitMQ

- **Decision**: `opentelemetry-instrumentation-aio-pika` in Orders (publisher) and Notifications (consumer). It writes W3C `traceparent` and `tracestate` into AMQP message headers and continues the trace on consume ([OpenTelemetry aio-pika instrumentation](https://opentelemetry-python-contrib.readthedocs.io/en/latest/instrumentation/aio_pika/aio_pika.html)). The outbox relay must publish under the context saved with the outbox row (the row stores `traceparent`), not the relay's own background context.
- **Rationale**: SC-005 and User Story 5 need one trace from checkout through the email. The outbox moves the publish out of the request, so the context has to be carried in the row.
- **Spike (Sprint 3, contract test)**: assert that the Notifications consume span shares the trace ID of the originating checkout. If the instrumentor creates a span link instead of a parent, extract the context manually in the consumer.
- **Alternatives considered**: a custom header injector without the instrumentor (more code to maintain); trace links only (fails SC-005's single-trace requirement).

## R10. Database backups with CloudNativePG

- **Decision**: use the Barman Cloud Plugin (`ObjectStore` resource, cluster `plugins` section, `Backup` with `method: plugin`) writing to MinIO, rather than the in-tree `spec.backup.barmanObjectStore`. Add cert-manager to `gitops/platform/`, because the plugin needs it.
- **Rationale**: in-tree Barman Cloud support has been deprecated since CloudNativePG 1.26 and is scheduled for removal ([migration guide](https://cloudnative-pg.io/plugin-barman-cloud/docs/migration/)). The removal version has moved several times, and recent release notes point to 1.31. Starting on the plugin avoids a forced migration mid-program.
- **Cost**: about 0.15 GB for cert-manager and the plugin. The memory budget in the plan is updated.
- **Session end**: no backup is created at the end of a session, because creating a `Backup` from `make down` would be a cluster write outside Argo CD (Principle I). Instead, see R14.
- **Restore**: the rebuild drill restores with a `bootstrap.recovery` cluster that references the same `ObjectStore`, replaying archived WAL to the latest point available.

## R11. Change events (FR-021)

- **Decision**: Argo CD Notifications with an `on-deployed` trigger posts a Grafana annotation (tags: `service`, `version`, `env`) through Grafana's HTTP API, and writes the same fields as a JSON log line that Loki stores.
- **Rationale**: annotations show releases on every dashboard, and the Loki record is queryable by the Project 2 correlation work. This writes only to the observability stack, not to cluster state, so Principle VIII still holds.
- **Alternatives considered**: a custom controller watching Argo CD Applications (more code); Git commit history alone (records when a change merged, not when it reached the cluster).

## R12. Traffic generator

- **Decision**: Locust in headless mode as a Deployment in each namespace, with a `LoadTestShape` that follows a daily-shaped curve. Peak rate, base rate and cycle length (default 2 hours) are set through environment variables in the GitOps overlay. Users are seeded synthetic accounts in Keycloak; purchases follow R6.
- **Rationale**: Locust is already in the plan's dependencies, and a shape class gives the FR-022 curve without a separate scheduler. The rate is set in Git, so changing it follows Principle I.
- **Alternatives considered**: k6 (good for the one-off SC-002 and SC-003 tests, still used there, but its JavaScript scenarios would duplicate the Python seed code).

## R13. Service-to-service authentication

- **Decision**: user requests carry the user's Keycloak access token from the BFF to each service. Service-to-service calls with no user (Payments worker → Orders, Orders sweeper → Payments) use a Keycloak client-credentials token per service. Each service checks audience and expiry. The two Stripe webhook routes are the only routes without a JWT; they authenticate with the Stripe signature instead.
- **Rationale**: FR-003 asks that every request be authenticated. The webhook exception is unavoidable and still authenticated, just by a different method.

## R14. Backing up at session end without writing to the cluster

- **Decision**: continuous WAL archiving through the Barman Cloud Plugin, with `archive_timeout` set to 60 seconds in each `Cluster`, plus a daily `ScheduledBackup` with `immediate: true` for the base backup. All of these are declared in Git. `make down` writes nothing to the cluster; it only reads. It waits until each `Cluster` reports continuous archiving as working and its most recent archived WAL is no older than 2 × `archive_timeout`, waits one more `archive_timeout`, then stops the node.
- **Rationale**: Principle I forbids anyone changing cluster state outside a Git commit applied by Argo CD, and that includes creating a `Backup` from a Makefile. With continuous archiving the data is already in MinIO when the session ends, so the session-end step becomes a read-only check that the archive is current. The recovery point is at most about one minute of writes, all of them synthetic.
- **Reading of FR-023**: "backed up when a session ends" is met by archiving that is current when the session ends, rather than by a separate backup job. The restore demonstration in the drill is unchanged.
- **Spike (Sprint 1, during T021)**: confirm where the plugin reports the last archived WAL time (the `Cluster` condition `ContinuousArchiving` and the `ObjectStore` status are the candidates), and that `archive_timeout` can be set in `spec.postgresql.parameters`. Write the field names into T013.
- **Alternatives considered**: commit a timestamped `Backup` manifest to the GitOps repo from `make down` (meets Principle I, but every session would need a pull request to a protected branch); record a session-end `Backup` as an exception to Principle I (keeps the simplest script, but makes the first exception to the rule the whole program depends on); hourly `ScheduledBackup` only (loses up to an hour of data).

## R15. CI hosts and how they are reached

- **Decision**:
  - **Jenkins controller** on the MacBook Air, installed with Homebrew `jenkins-lts` and run by a LaunchAgent bound to `127.0.0.1:8080`, started and stopped by hand with the lab session. Its configuration (plugins, the mini agent, jobs) is code in `infra/jenkins/` (Configuration as Code).
  - **Mini agent**: the controller starts it over SSH with a dedicated key (`~/.ssh/sv_jenkins_agent`), using the Air's existing SSH access to the mini. On the mini the key is `restrict`ed: commands only, no forwarding and no pty. There is no inbound agent port (50000). GitHub cannot reach Jenkins, so jobs poll Git every 5 minutes.
  - **Code quality**: SonarQube Cloud's free plan, CI-based analysis from the app repository's GitHub Actions, one SonarQube Cloud project per service in the monorepo, and the quality gate reported on each pull request by the SonarQube Cloud GitHub App.
  - **The Intel MacBook Pro leaves the lab.** The platform runs on two machines: the mini (cluster and build agent) and the Air (workstation and Jenkins controller).
- **Rationale**: the Air is on whenever a lab session runs, because sessions are driven from it, so Jenkins is available exactly when there is a cluster to change. Binding to loopback means nothing listens on the home network (Principle VI) without a tunnel or a firewall change. The controller with zero executors needs about 0.5–1 GB, which fits next to the Air's other work, and stopping it between sessions frees that memory. SonarQube Cloud is free for public repositories, adds pull request decoration, and needs no machine.
- **Cost**: $0.
- **Trade-offs accepted**: the Air is a personal laptop, so it now holds the agent key and the Jenkins credentials store; neither gives access to the cluster, whose credentials stay on the mini. Memory is tighter when a local model runs at the same time; stop Jenkins first if needed.
- **Spike (Sprint 1, T105)**: confirm the SonarQube scan action runs on `ubuntu-24.04-arm`. If it does not, run only the scan job on `ubuntu-24.04`; analysis produces no image, so the arm64 rule for runtime images is unaffected.
- **Alternatives considered**: Jenkins on the Intel Mac (needs a third machine on all session, and a reverse SSH tunnel plus firewall rules to stay closed to the home network; tried and dropped on 2026-10-30); Jenkins on the mini (competes with the cluster for the 4 GB left outside Docker); a GitHub Actions self-hosted runner on the mini instead of Jenkins (simpler, but removes the Jenkins-versus-Actions comparison the program plans to publish); self-hosted SonarQube (about 2 GB and a server to patch).
- **Constitution impact**: the Additional Constraints line "Intel MacBook Pro 8 GB runs Jenkins and SonarQube only" no longer matches, and the Air's line gains the Jenkins controller. This needs a PATCH amendment with an ADR (T106).

---

## Plan changes from this research

| Research | Change to plan.md |
| --- | --- |
| R1 | Kind cluster is one node; memory row updated |
| R2 | Ingress binds to loopback until Tailscale; Principle VI deviation tracked |
| R3 | One Stripe sandbox per environment |
| R5, R8 | Reconciliation loop, inbox and outbox added to key design decisions |
| R10 | Barman Cloud Plugin and cert-manager; memory row updated |
| R14 | `make down` only checks that WAL archiving is current; it creates no `Backup` |
| R15 | Jenkins controller on the Air, bound to loopback; SonarQube Cloud for code quality; the Intel Mac leaves the lab |

## Tasks

These decisions are applied in [tasks.md](./tasks.md): the spikes are T008, T009 and T052; the Kind module is T010; the per-environment Stripe and certificate Secrets are T012; cert-manager, the Barman Cloud Plugin and WAL archiving are T017 and T021; the read-only session-end check is T013; reconciliation is T045 and T069; the Orders outbox relay is T065; the trace continuity check is T084; the Jenkins controller, its Air setup, SonarQube Cloud and the constitution amendment are T103–T106.
