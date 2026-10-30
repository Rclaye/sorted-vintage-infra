# Quickstart: Validate Project 1 End to End

**Feature**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md)

This guide proves the feature works, from an empty Mac mini to a traced purchase. It is also the script for the Gate 1 rebuild drill. Commands describe the intended interface. The Makefile targets and scripts are built in Sprints 1 to 3 (see [tasks.md](./tasks.md)), and each sprint's `verify_sprintN.sh` automates the checks that apply so far.

## Prerequisites

- Mac mini with Docker Desktop (memory set to 12 GB) and the [Brewfile](../../scripts/Brewfile) tools, plus `mkcert` and `stripe`.
- Clones of `sorted-vintage-infra`, `sorted-vintage-app` and `sorted-vintage-gitops` on the mini.
- Two Stripe test-mode sandboxes, one for dev and one for prod, with Connect enabled ([research R3](./research.md#r3-stripe-one-sandbox-per-environment)).
- `infra/terraform/bootstrap/secrets.auto.tfvars` (git-ignored) holding both sandboxes' test keys, database passwords and the mkcert certificate.
- On the MacBook Air: the mkcert root CA trusted, `/etc/hosts` mapping `dev.sortedvtg.lan`, `prod.sortedvtg.lan`, `grafana.sortedvtg.lan`, `argocd.sortedvtg.lan` and `mail.sortedvtg.lan` to `127.0.0.1`, and the tunnel open:

```bash
ssh -N -L 8443:127.0.0.1:443 mac-mini
```

Browser URLs below use `https://<host>:8443`.

## 1. Rebuild from nothing (User Story 3, SC-004)

On the mini, from `sorted-vintage-infra`:

```bash
make rebuild
```

`make rebuild` runs `terraform apply` for `cluster` and then `bootstrap`, and waits until every Argo CD Application is `Synced` and `Healthy`. Start a timer when you run it.

**Expected**: no manual step; `kubectl get applications -n argocd` (read-only) lists every app as `Synced Healthy`; the seed job has created demo sellers and listings in both namespaces; the elapsed time is under 30 minutes once a purchase in step 3 succeeds. Record the time in the sprint retro (Principle II).

## 2. Seller lists an item (User Story 1, SC-001)

1. Open `https://dev.sortedvtg.lan:8443`, sign up with a new email, and confirm it from the Mailpit inbox at `https://mail.sortedvtg.lan:8443`.
2. Go to **Sell an item**, fill in the form and add two photos, then publish.
3. You are redirected to Stripe Express onboarding. Complete it with Stripe's test values and return to the site.
4. The listing publishes.
5. In a private window (signed out), search for the brand.

**Expected**: the listing appears in browse within 5 seconds and in the search results; publishing after onboarding took under 2 minutes; onboarding took under 5 minutes. Uploading a `.txt` file renamed to `.jpg`, or an 11 MB image, is rejected with a message and nothing is stored.

## 3. Buyer purchases it (User Story 2)

Sign in as a second account and buy the listing. Pay with test card `4242 4242 4242 4242`.

**Expected**:

- While the payment page is open, the listing shows as unavailable to a third visitor.
- After paying, the order page shows **Paid**, the listing shows **Sold**, and Mailpit has the buyer's confirmation and the seller's sale email.
- `GET /orders/{id}/ledger` on Payments returns a platform entry of 10% and a seller entry for the rest, summing to the price.
- Buying your own listing is refused. Paying with the decline card `4000 0000 0000 0002` releases the item.

## 4. Follow the purchase (User Story 5, SC-005)

In Grafana, open Tempo and search for the order ID from step 3.

**Expected**: one trace covers BFF → Orders → Listings → Payments, the webhook path back into Orders and Listings, and the Notifications consume and send spans. Opening any log line from that trace in Loki shows the same `trace_id`. The dashboards show a deployment annotation for each service (FR-021).

## 5. Ship a change through review (User Story 4)

1. In `sorted-vintage-app`, change a response field in one service and merge the PR.
2. Wait for the build workflow to commit the new tag to `gitops/services/<name>/overlays/dev`.
3. Open the promotion PR to prod, approve it and merge it.
4. Revert the promotion commit.

**Expected**: dev runs the new version with no manual step; prod changes only after the promotion PR merges; after the revert, prod returns to the previous version. A build with a critical Trivy finding publishes no image.

## 6. Policy holds by every route (SC-010, FR-027)

Apply each manifest in `gitops/tests/policy/bad/` (runs as root, no limits, image from outside GHCR):

```bash
kyverno apply gitops/policies/ --resource gitops/tests/policy/bad/
```

Then open a PR that adds the same files under a service overlay.

**Expected**: the CLI reports a failure for each file; the PR's policy check fails; and if the PR is merged anyway on a test branch synced to dev, Argo CD reports each resource as rejected by admission.

## 7. Notifications outage (SC-007)

Scale Notifications to zero in `gitops/services/notifications/overlays/dev`, merge, run purchases for 30 minutes, then revert.

**Expected**: every purchase completes while Notifications is down; after the revert, every queued email arrives in Mailpit within 5 minutes; a message forced to fail 5 times appears in `notifications.orders.dead`.

## 8. No double sales (SC-003) and latency (SC-002)

```bash
make loadtest-double-sell ENV=dev   # 1,000 concurrent purchase attempts across 100 items
make loadtest-baseline ENV=dev      # the generator's baseline rate for 15 minutes
```

**Expected**: zero listings with more than one `paid` order (the test queries Orders and reports the count); p95 checkout time under 2 seconds, excluding time on the payment page.

## 9. Add a service from the template (User Story 7, SC-009)

```bash
copier copy app/templates/service-fastapi app/services/hello
```

Commit the generated service and its `gitops/services/hello/{base,overlays}` folder in one PR, and merge it. Start a timer at `copier copy`.

**Expected**: `hello` is healthy in dev with a dashboard, with no change to `gitops/platform/` or `bootstrap/`, in under 30 minutes.

## 10. Sessions keep their state (FR-023, FR-024, SC-008)

```bash
make down
make up
```

**Expected**: `make down` confirms each database's WAL archive is less than 2 minutes old, writes nothing to the cluster, and then stops the node. With the mini powered on, `make up` returns every app to `Healthy` in under 10 minutes. The orders from step 3 and the previous session's dashboard history are still there. A payment completed while the lab was down is applied by Payments reconciliation within 5 minutes of start ([research R5](./research.md#r5-events-missed-while-the-lab-is-off)).

## 11. Restore during the drill (FR-023)

```bash
make destroy
make rebuild
```

**Expected**: with the restore mode committed as `recovery` in `gitops/platform/postgres/` (T076), the rebuilt databases hold the orders from before `destroy`, restored from MinIO, whose volume lives outside the cluster.

## 12. Traffic runs all session (User Story 6)

Leave the platform running for 4 hours.

**Expected**: every service has non-zero request rate in every 5-minute window; rates rise and fall on the configured 2-hour cycle; the order count grows; every generated payment is in Stripe test mode with synthetic users.
