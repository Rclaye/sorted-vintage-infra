# Sprint 2 Retrospective

## Outcome

Sprint 2 delivered User Story 1 in dev: a visitor signs up through Keycloak, onboards with Stripe, lists an item with photos and publishes it, and anyone can browse, search and see seller pages. Richard's timed walkthrough on 2026-11-11 met the targets (onboarding about 4 minutes, listing under 2, in browse at once). A seed job fills dev with three sellers and 50 listings, and `verify_sprint2.sh` checks the story end to end. It passed every check from the workstation on 2026-11-12, with a listing in search 0.05 seconds after publishing, and it now runs read-only at the end of every Jenkins `infra-terraform` build. Pods use about 8.3 GiB of the node's 11.9, so Sprint 3 starts with less room than Sprint 1 projected.

## Completed Work

Each ticket's acceptance checks, with evidence, are in [docs/verification-log.md](../../docs/verification-log.md#sprint-2).

### Ticket 2.1: Retire the Sprint's Risks First (T052)

Spikes in [spikes.md](./spikes.md): Stripe's hosted onboarding returns to the lab's `.lan` address on port 8443, Stripe refuses an API-side terms acceptance for a seller (so demo sellers are onboarded by hand once), and scripts sign in through the BFF login form instead of a direct-grant client.

### Ticket 2.2: Java in CI, the BFF Ingress and Keycloak From Git (T116–T118, T120)

The build workflow learned Gradle; the BFF got its Ingress; keycloak-config-cli applies the realm files on every sync, so no client setting is changed by hand.

### Tickets 2.3 and 2.4: Listings (T033, T035–T041)

A Spring Boot service with Flyway, full-text search, drafts, photos in Garage behind Listings' own photo route, seller profiles, and the pending-photo cleanup (app #9).

### Ticket 2.5: Payments and the Stripe Forwarder (T034, T042–T045, T049, T050)

Accounts v2 onboarding, payout status, the Connect webhook through `stripe listen`, and the 5-minute reconciliation (app #10, #11; gitops #35). The live run found two requests the test fakes had accepted.

### Ticket 2.6: Publish, Sign-In and the Pages (T046–T048)

Publishing goes through Payments; the BFF signs users in with PKCE and keeps their tokens in one encrypted cookie (app #12–#14, infra #42, gitops #42, #45).

### Ticket 2.7: Seed Data (T051)

- A spike on 2026-11-12 showed a pod can drive the BFF login form by sending the browser's names to Traefik's Service and keeping them for TLS and the Host header ([spikes.md](./spikes.md#in-cluster-sign-in-t051-t115)).
- Payments `PUT /connected-accounts/{sub}` links a seller to an account onboarded by hand; only the `seed` client may call it, and only in dev (app #15, gitops #48).
- Terraform publishes Secret `seed-sellers` from `seed_sellers` in `secrets.auto.tfvars`, and ConfigMap `lab-tls-cert`, the public half of the lab certificate that the job pins (infra #44, #46).
- The seed job, `services/seed` in the app repo, runs as a PostSync hook of `seed-dev` (app #16, gitops #52). It creates or updates the sellers, links them, and publishes only the listings still missing, with photos it draws itself. Its first run created 50 listings. A second run in the lab is still to be seen; the tests show it only fills gaps.
- The verify seller was created by the job without a link, onboarded by hand (`acct_1Uao…`), and its id then added to `seed_sellers`.

### Ticket 2.8: Verify and Measure (T115, T113, T119)

- `verify_sprint2.sh` runs `verify_sprint1.sh`, then reads health, the BFF through its Ingress with the mkcert CA, the seed job and its listings. From the workstation it also checks unsigned webhooks are refused and runs `verify_selling.sh` on the lab host, which signs in as the verify seller, checks bad uploads are refused, publishes a listing, times it into search and deletes it (infra #47). The BFF gained the delete action it needed (app #17).
- Memory re-measured below.

## Memory: Measured Again (T119)

Measured on 2026-11-12 with all 35 Argo CD apps Synced and Healthy, the same way as T032: container working sets from Prometheus, read through the API server proxy.

| | Sprint 1 (2026-11-05) | Sprint 2 (2026-11-12) |
| --- | --- | --- |
| Pods, now | 6.16 GiB | 8.29 GiB |
| Pods, 24-hour median / 95th percentile | 5.95 / 7.25 GiB | 7.96 / 8.37 GiB |
| Pods, 24-hour peak | above 9 GiB for about 10 minutes, during a start | 8.81 GiB |
| Node container, `docker stats` | 7.1 of 11.9 GiB | 9.28 of 11.91 GiB |
| `kube-apiserver` | 1.46 GiB | 1.54 GiB |
| Lab host memory free | 36% | 55% |

By namespace now: monitoring 2.21 GiB, kube-system 1.97, sv-dev 1.02, sv-prod 0.94, Argo CD 0.90, Keycloak 0.68, everything else under 0.2 each.

| Service, per replica | sv-dev | sv-prod |
| --- | --- | --- |
| Listings (JVM) | 459 MiB | 407 MiB |
| Payments | 100 MiB | 78 MiB |
| BFF | 95 MiB | 50 MiB (2 replicas) |
| Stripe forwarder | 76 MiB | 86 MiB |
| Postgres, RabbitMQ, Garage, Mailpit | 315 MiB | 295 MiB |

The seed job adds nothing at rest: it runs for a few minutes after a sync, inside a 192 MiB limit.

What it means:

- **Still under the 11 GB line**; dev does not need to scale to zero, and the node has about 2.6 GiB left.
- **Sprint 1's projection was reached a sprint early.** It expected pods near 8 GiB median once every service ran; that is today, with Orders, Notifications and the traffic generator still to come in Sprint 3. If they are as small as Payments they add about 0.5 GiB and put the 95th percentile near 9 GiB.
- **Listings is half the service memory.** A tighter JVM heap in prod is the first lever if room runs short. Monitoring grew by about 0.5 GiB with real traffic in Loki and Tempo; retention is the second lever.

## Changes From the Spec

| Planned | Actual | Why |
| --- | --- | --- |
| Seed job in `app/tools/seed/` | `app/services/seed/` | The build workflow builds, scans and deploys `services/*`; the seed job reuses that path instead of a second workflow (decided 2026-11-12) |
| Each demo seller onboarded by hand before the job runs | The verify seller is created by the job first, unlinked, then onboarded | `seed_sellers` only takes real account ids, and onboarding needs the user to exist |
| Webhook checks "on both webhooks" | The Connect webhook in both namespaces | `/webhooks/stripe` for payment events arrives with US2 in Sprint 3 |

## What We Learned

- **A spike's shortcut is not the design.** The sign-in spike trusted whatever certificate Traefik served; it proved the path but not the identity. The job pins the certificate Terraform publishes instead, and the spike note says so.
- **Order the hand steps with the code.** The first Jenkins apply ran before the `seed_sellers` block was added and created an empty Secret; the verify seller could only be onboarded after the job created it. Writing the order down before each PR avoided a third surprise.
- **`set -o pipefail` and SIGPIPE.** `tr < /dev/urandom | head` ended the selling check silently; generate random names in one process.
- **A stale clone fails a check for no real reason.** The lab host's infra clone was 22 commits behind, so its plan wanted to remove a resource newer code had added. Fast-forward it before reading a plan from it.

## Follow-Ups

- [x] Re-measure memory at the end of Sprint 2 (Sprint 1 follow-up, above).
- [x] T113: the 5-second browse check, in `verify_sprint2.sh`.
- [ ] Platform hygiene, one gitops PR: redact `whsec_` values before Loki, tune cert-manager's liveness probe for Docker Desktop clock jumps, drop `/healthz` and `/metrics` spans in the OTel Collector.
- [ ] Keep the lab host's infra clone current: `verify_sprint1.sh` plans from it.
- [ ] Watch Listings' heap and monitoring retention as Sprint 3's services arrive.
- [ ] Promote the BFF with the pages and the delete action to prod (promote workflow, approval).
- [ ] Sprint 3 is large (about 50 tasks): consider splitting it.
