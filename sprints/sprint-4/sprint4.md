Sorted Vintage — Sprint 4 Actionable Engineering Specification
Document Status: Draft for review
Target Release: Sprint 4, Operate It, Then Gate 1 (Nov 19 – Dec 10, 2026)
Author: Platform Engineering
Source: specs/001-marketplace-local-cloud/tasks.md, Phases 5 to 10 (User Stories 3 to 7, T076–T102), T110, T114, T121–T123, T125; the outline in [sprint3.md](../sprint-3/sprint3.md) section 6

1. Executive Summary & Sprint 4 Objective

Sprint 3 closed on 2026-11-18, eight days early, with User Story 2 working and checked on every Jenkins build. Sprint 4 starts the next day and keeps its end date. It turns the marketplace into something that is operated, not just built: the lab is rebuilt from Git with its data restored (User Story 3), releases are shown to be safe and signed (User Story 4), one purchase can be followed through every service with its changes and objectives on the same screen (User Story 5), real-looking traffic runs all the time (User Story 6), a new service comes from the template in one pull request (User Story 7), and every log reaches Loki (T125). It ends with Gate 1: SC-001 to SC-010 checked where a script can check them (`verify_sprint4.sh`, T100), the ADRs, the case study and the final README.

Sprint Objective
`verify_sprint4.sh` is green from the workstation and in Jenkins, running `verify_sprint3.sh` first and then every success criterion a script can check; the rebuild drill reaches a working purchase from an empty lab host in under 30 minutes (SC-004) and restarts in under 10 (SC-008); a sampled purchase is one trace across all five services (SC-005); the traffic generator runs in dev at its baseline and 95% of checkouts finish in under 2 seconds (SC-002); with Notifications stopped for 30 minutes no sale is lost and every email arrives within 5 minutes of recovery (SC-007); a new service is healthy in dev from the template in under 30 minutes (SC-009); and memory stays under the 10 GiB trigger with traffic and the log shipper running.

Decisions carried in
- Order matters: each ticket builds on the one before (sprint3.md section 6). The rebuild comes first, while nothing else is moving; traffic before logs and tracing, so they have something to show.
- A spike before anything risky reaches the lab (on `sv-spike` or a throwaway container), recorded in `sprints/sprint-4/spikes.md`.
- Evidence that tasks.md still files under `sprints/sprint-3/` (`evidence.md`, `sessions.md`) is written to `sprints/sprint-4/` instead: those tasks moved here when Sprint 3 was split (2026-11-12).
- Settings before images; one ticket per pull request where possible; prod is only read by the verify scripts, and a promotion always waits for approval (ADR-0002).
- New dependencies and installs are asked for first, named, with where they go. Pinned with `--exclude-newer` two weeks back; container images from releases at least two weeks old.
- Scripted lab checks reuse `services/seed/app/site.py` in a venv from the seed service's pinned requirements (Ticket 3.8), so they need nothing new.
- Each SonarCloud project must be public, on `main` and bound before its first merge (Sprint 3 retro: three were not). A PR check named without the `[sv-name]` prefix is the sign.

2. Lab Changes in Sprint 4

| Added | Where | Memory (measured services as the yardstick) |
| --- | --- | --- |
| Restore mode for Postgres, chosen per environment in Git (T076, T110) | `gitops/platform/postgres/` | none |
| Locust traffic generator, headless (T088–T091) | `sv-dev` (and `sv-prod` at a lower rate, or 0 until decided) | about 150 to 300 MiB each, to be measured |
| 50 synthetic buyers and sellers per realm (T090) | Keycloak, by the seed job | small (Keycloak's database) |
| Log shipper (T125) | a DaemonSet or Deployment beside Loki in `monitoring` | about 100 to 250 MiB, to be measured |
| Argo CD Notifications controller and change events (T114, T086) | `argocd` | about 50 MiB |
| Dashboards, SLOs, data sources (T085, T087, T123) | Grafana, as code | small |
| Image signatures and SBOMs, and the Kyverno policy that checks them (T122) | GHCR, `gitops/policies` | Kyverno's footprint grows slightly |

Measured before the sprint (memory checkpoint 1, Sprint 3 retro): pods 8.23 GiB now, 24-hour median 8.18 and 95th percentile 8.56 GiB, node container 9.17 of 11.91 GiB. Expected after: pods about 9 to 9.5 GiB median. **Memory checkpoint 2** comes after the traffic generator (Ticket 4.2) and **checkpoint 3** after the log shipper (Ticket 4.3). Trigger: pods' 95th percentile over 10 GiB. Levers in plan.md's order: a fixed heap for Listings in prod, prod BFF at 1 replica, shorter Loki, Tempo and Prometheus retention, then Docker Desktop at 13 GB (Richard's call; Ollama off during sessions).

3. Actionable Engineering Tickets & Implementation Specs

Ticket 4.1 — Rebuild From Git (T076–T079, T110)
Owner: Platform Engineer
Repos: gitops (`platform/postgres`), infra (`jenkins/Jenkinsfile`, `docs/runbooks/rebuild.md`, `sprints/sprint-4`)
Story: As the platform owner, I can destroy the lab and bring it back from Git, with the data restored, by one command.

Implementation Requirements:
- **Spike first** on `sv-spike`: a CloudNativePG cluster bootstrapped by recovery from a Barman Cloud Plugin backup in Garage, including the Keycloak database, and what Argo CD does while the cluster is recovering.
- T076 and T110: the restore mode is a per-environment choice committed in Git (for example a `recovery` component each environment overlay includes or not), changed only by pull request; Terraform has no restore variable.
- T077: a `rebuild-drill` stage in the Jenkinsfile (destroy, apply, restore, wait for health, the scripted purchase from `verify_purchase.py`) that records the elapsed time as a build artifact; it needs both of Jenkins' approvals, like `DESTROY`.
- T078: `docs/runbooks/rebuild.md`: `make destroy`, `make rebuild`, switching the restore mode by pull request, what survives (Garage data on the host) and what does not.
- T079: `make down` then `make up` with the host powered on, healthy in under 10 minutes with previous orders, dashboards and accounts present (`verify-buyer` can still sign in), recorded in `sprints/sprint-4/sessions.md` (SC-008).

Acceptance Criteria Verification:
- The drill runs once through Jenkins with Richard's approvals: an empty lab host reaches a working purchase in under 30 minutes (SC-004, recorded as T098 in Ticket 4.7); previous orders and accounts are present afterwards.

Ticket 4.2 — Traffic (T088–T091)
Owner: Application Engineer, Platform Engineer for T091
Repos: app (`tools/traffic`, `services/seed`), gitops (`services/traffic`), infra (`docs`)
Story: As the platform owner, I want the marketplace used all the time, so metrics, logs, traces and the AIOps work have something real to look at.

Implementation Requirements:
- Locust is a new dependency (research R12): ask before adding it; pin it like the others. The generator image follows the template's Dockerfile rules.
- T090 first: the seed job creates 50 synthetic buyers and sellers per realm, with credentials in a generated Secret the generator reads (Terraform or the seed job; decide in the spike, keeping secrets out of Git).
- T088: browse, search, list and buy through the BFF routes, like `verify_purchase.py`; purchases confirm with `pm_card_visa`, and a configurable share with `pm_card_chargeDeclined` (R6). Some checkouts are left unpaid, so Orders' expiry cancels through Payments' cancel route: the open check carried from Ticket 3.5.
- T089: a `LoadTestShape` following a daily curve, `BASE_RPS`, `PEAK_RPS`, `CYCLE_MINUTES` (default 120) from the overlay (FR-022).
- T091: headless in `gitops/services/traffic/{base,overlays/dev,overlays/prod}`, rates in each overlay's ConfigMap, lower in dev; prod's rate stays 0 until prod's services are promoted.
- Sold items accumulate: decide how the generator keeps a supply of listings (its sellers list new items) so seeded listings are not used up.
- Memory checkpoint 2 after a day of traffic.

Acceptance Criteria Verification:
- In dev the generator follows its curve for at least one full cycle; purchases, declines and expiries appear in Orders, Payments' ledger and Mailpit; an expired order's PaymentIntent is cancelled through Payments (closes the 3.5 open check); memory checkpoint 2 is recorded.

Ticket 4.3 — Logs (T125)
Owner: Platform Engineer
Repos: gitops (`platform/observability`)
Story: As the platform owner, I want every container's logs in Loki with the labels to find them, and no secret in them.

Implementation Requirements:
- **Spike first**, with traffic running: the shipper (Grafana Alloy or Promtail; choose by footprint and support, ask before adding it), on `sv-spike` and then the lab; container logs from `sv-dev`, `sv-prod` and the platform namespaces with namespace, pod, container and service labels; JSON lines parsed so `trace_id`, `order_id` and `level` are queryable.
- `whsec_` redaction applied again at the shipper (defence in depth after gitops #54); a test line proves it.
- Retention set against the memory budget; memory checkpoint 3.

Acceptance Criteria Verification:
- A purchase's lines from all five services are found in Loki by its `order_id`; a planted `whsec_` value is redacted in Loki; memory checkpoint 3 is recorded.

Ticket 4.4 — Follow One Purchase (T084–T087, T114, T123)
Owner: Platform Engineer, Application Engineer for T084
Repos: app (`tests/e2e`), gitops (`platform/kube-prometheus-stack`, `platform/argocd-notifications`), infra (`terraform/modules/argocd-bootstrap`, `docs/slo.md`)
Story: As an operator, I can follow one purchase from the browser to the email, see what changed and when, and know whether we are within our objectives.

Implementation Requirements:
- T084: `app/tests/e2e/test_trace.py` completes a purchase (reusing `verify_purchase.py`'s steps) and asserts through Tempo's API that one trace holds spans from the BFF, Orders, Listings, Payments and Notifications' consume span (SC-005). Tempo answers at `http://tempo.monitoring:3200`; `order_id` is already on every span (T083).
- T085: Grafana data sources: Tempo with trace-to-logs on `trace_id` and search by `order_id`; Loki with a derived field linking `trace_id` to Tempo.
- T114 then T086: enable the Argo CD Notifications controller (Terraform turns it off today), then an `on-deployed` trigger posting a Grafana annotation tagged `service`, `version`, `env` and the same fields as a JSON log line (R11, FR-021). Terraform change first, through Jenkins.
- T087: dashboards as code: one RED dashboard per service and one checkout-path dashboard, each showing deployment annotations.
- T123: `docs/slo.md`: availability and latency SLIs for browse (BFF, Listings) and checkout (BFF, Orders, Payments), targets and an error-budget window that survives the lab's sessions; the choice recorded in research.

Acceptance Criteria Verification:
- From one purchase's `order_id`, Grafana goes from its logs to its trace and back; the trace test passes; a deployment shows as an annotation on its service's dashboard; the SLO document exists and its SLIs are on a dashboard.

Ticket 4.5 — Safe Releases (T081, T082, T122)
Owner: Platform Engineer
Repos: app (`.github/workflows/build.yml`), gitops (`policies`), infra (`sprints/sprint-4/evidence.md`)
Story: As the platform owner, I want proof that a vulnerable image cannot ship, that a release can be undone quickly, and that only images we built can run.

Implementation Requirements:
- T081: a throwaway branch whose base image has a known critical CVE fails Trivy in `build.yml` and publishes nothing; evidence in `sprints/sprint-4/evidence.md`; the branch is deleted.
- T082: roll back a prod promotion by `git revert` through prod-gate, timing it until prod runs the previous version. It needs a promotion first: promote one service to prod with Richard's approval (the BFF, whose prod is the old stub).
- T122: **spike first**: cosign keyless signing by digest with GitHub OIDC (`id-token: write`) and an SPDX SBOM from syft attached as an attestation, then a Kyverno `verifyImages` policy in `gitops/policies`, first in Audit, then Enforce once every running image is signed. New tools in CI (cosign, syft actions): ask first.

Acceptance Criteria Verification:
- The vulnerable build fails with nothing pushed; the rollback is timed and recorded; an unsigned image is refused at admission and a signed one runs, in dev and prod.

Ticket 4.6 — A New Service From the Template (T092, T093)
Owner: Application Engineer, Platform Engineer
Repos: app (`templates/service-fastapi`), gitops
Story: As a developer, I get a new service running in dev from the template with one pull request per repo and no platform change.

Implementation Requirements:
- T092: the template also generates `gitops/services/<name>/{base,overlays}` (with an `images` newTag line from the start, Ticket 3.4 lesson) and a RED dashboard ConfigMap.
- T093: generate `hello`, merge its PRs, time it against SC-009 (template to healthy in dev under 30 minutes), record it in `sprints/sprint-4/evidence.md`, then remove `hello`. Its SonarCloud project must be public, on `main` and bound before the first merge.

Acceptance Criteria Verification:
- `hello` is healthy in dev in under 30 minutes from `copier copy` with one PR to each of app and gitops; it is removed afterwards and nothing of it remains in the lab.

Ticket 4.7 — Gate 1 (T094–T102, T121)
Owner: Platform Engineer, Richard for the timed manual checks
Repos: infra, app (`Makefile`)
Story: As a reviewer, I can see every success criterion checked, with its number and its evidence, and read why the platform is built this way.

Implementation Requirements:
- T100: `sprints/sprint-4/verify_sprint4.sh`, running `verify_sprint3.sh` first, then SC-001 to SC-010 where a script can check them; Jenkins runs it with `MINI=local`, reads only.
- T094 (SC-001, timed by hand, as quickstart step 2 was), T095 (SC-002: `make loadtest-baseline ENV=dev`, 15 minutes at the baseline, p95 checkout under 2 s excluding the payment page), T096 (SC-007 outage drill: Notifications stopped 30 minutes), T097 (SC-010: quickstart step 6, every policy break rejected in CI and at admission), T098 (SC-004: the full rebuild drill through Jenkins), each in `sprints/sprint-4/evidence.md` and the verification log.
- T099: build Listings in Jenkins as well as Actions, on the lab host agent, for the comparison article.
- T101: ADRs 0003 to 0007 (and others found on the way); T102: the Gate 1 case study and "Jenkins or GitHub Actions?"; T121: the final front-door README with measured results linked to the verification log.
- `sprint4_retro.md`, the verification-log rows, the handoff and the lab map; tasks ticked at the sprint's close.

Acceptance Criteria Verification:
- `verify_sprint4.sh` passes from the workstation and in Jenkins; every SC has a verification-log row with its result and evidence; the README links each number to its row.

4. Sprint Verification

Run `sprints/sprint-4/verify_sprint4.sh` from the workstation with the lab up. Jenkins runs it with `MINI=local` at the end of every `infra-terraform` build once it is on `main`, reading only. From the workstation it may write to `sv-dev` (scripted purchases, the load checks); it never writes to prod. The timed manual checks (SC-001, the rebuild drill, the outage drill) are run once each and recorded.

5. Out of Scope for Sprint 4

T124's Drain3 log analysis (backlog, after Sprint 4); Tailscale and any access beyond the SSH tunnel; production use of real money or real email; a second cluster or node; Project 2 (change correlation) and the later AIOps projects.

6. Risks

| Risk | Mitigation |
| --- | --- |
| The rebuild drill loses data or leaves the lab half-built | Spike recovery on `sv-spike` first; Garage data on the host survives `destroy`; the drill needs two approvals; run it when nothing else is in flight |
| Traffic plus the log shipper push memory past the trigger | Checkpoints 2 and 3 after each; levers in plan.md's order; shipper retention set before it runs |
| Kyverno `verifyImages` in Enforce blocks running workloads | Audit first; Enforce only once every running image (platform charts included) is signed or exempted by name |
| Rate limits in Stripe's test mode under constant traffic | The generator's rates stay well under 25 requests a second; confirms throttled as in T058 |
| Gate 1 work crowds out the operational tickets | Tickets in order; Gate 1's writing (ADRs, case study) can start once 4.4 is done |
