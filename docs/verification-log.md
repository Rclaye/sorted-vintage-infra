# Verification log

Every acceptance check from the sprint tickets, with how it was checked, the result and where the evidence is. Automated checks also run in `sprints/sprint-N/verify_sprintN.sh`, which Jenkins runs at the end of every `infra-terraform` build; this log is mainly for the checks a script cannot do on its own: timings, approvals, drills, and anything done by hand.

**How to add an entry:** when a ticket closes, add one row per acceptance check. Say what was run, what came back, the date, and a link (PR, build number, `spikes.md` section or retro). If a check was skipped or only partly done, mark it **Open** and list it under [Open checks](#open-checks) instead of leaving it out.

Status: **Pass**, **Open** (not done or not recorded), **Partial** (done, but not the way the ticket asks).

## Open checks

| Ticket | Check | Why open | When |
| --- | --- | --- | --- |
| (none) | Every Sprint 2 check has run; Sprint 2 closed on 2026-11-12 (Tickets 2.7 and 2.8 below) | | |

The three checks that were never run in Sprints 0 and 1 (two from 0.2, one from 1.4) were run on 2026-11-05; see their rows below.

## Sprint 0

| Ticket | Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- | --- |
| 0.1 | The old SonarQube token is revoked and the old RDS password no longer works | The AWS account that held RDS, EC2 and the SonarQube host no longer exists; the class SonarQube server is believed gone | Pass, by removal | 2026-10-28 | Sprint 0 retro |
| 0.1 | `audit-old-secrets.sh` reports zero findings, or each is listed with its fix | gitleaks over 12 public repos found nothing; the file-history check found Terraform state and tfvars in two repos, which were made private | Pass | 2026-10-28 | Sprint 0 retro |
| 0.2 | A commit with a test AWS key is blocked locally | Test commit with a fake key | Pass: gitleaks rule `aws-access-token` blocked it | 2026-10-28 | Sprint 0 retro |
| 0.2 | ...and, if forced, fails the `checks` workflow | Randomly generated fake AWS-style key ID committed with `--no-verify` on a throwaway branch and PR | Pass: `secret-scan` failed, gitleaks rule `aws-access-token`; GitHub push protection did not block a key ID alone, so gitleaks is the layer that caught it. PR closed unmerged, branch deleted | 2026-11-05 | infra #28 (closed) |
| 0.2 | A direct push to `main` is rejected | Empty commit pushed to `main` from a throwaway clone, after confirming the ruleset has no bypass actors | Pass: "push declined due to repository rule violations: changes must be made through a pull request"; `main` unchanged | 2026-11-05 | ruleset `protect-main` |
| 0.2 | All three repos show a green `checks` run on their first PR | First PR in each repo | Pass: `pre-commit` and `secret-scan` green | 2026-10-28 | Sprint 0 retro |
| 0.3 | `kind version`, `terraform version`, `docker info` succeed on the lab host | Ran on the lab host | Pass; disk freed from 7.8 GB to 73 GB first | 2026-10-28 | Sprint 0 retro |
| 0.4 | `ssh lab-admin hostname` succeeds with key login | From the workstation | Pass | 2026-10-28 | Sprint 0 retro |
| 0.5 | Both ADRs merged by PR with green checks; spec, plan and tasks committed | ADRs in `docs/adr/`; Spec Kit workspace merged | Pass | 2026-10-30 | Sprint 0 retro; infra #2 |

## Sprint 1

### Ticket 1.1: confirm the research decisions

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| Kind survives `docker stop` / `docker start` with its data | Throwaway cluster with a PVC-backed pod | Pass: API back in 4 s, data intact | 2026-11-01 | `spikes.md` T008 |
| Stripe: one signing secret per sandbox covers platform and connected-account events | Two `stripe listen` sessions and a receiver that only logs whether signatures verify | Pass, with the move to Accounts v2 (R17) | 2026-11-01 | `spikes.md` T009 |
| Three merged PRs with the new hooks and green checks | | Pass | 2026-11-02 | infra #6, app #1, gitops #1 |

### Ticket 1.2: cluster and Argo CD from one Terraform apply

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `terraform apply` for `cluster` then `bootstrap` succeeds, and a second plan shows no changes | Applied on the lab host as `bot`; plans re-run by the verify script | Pass | 2026-11-02, rechecked 2026-11-05 | infra #7; `verify_sprint1.sh` |
| Port 443 bound to `127.0.0.1` only | `docker port sorted-vintage-control-plane 443` | Pass (80 too) | 2026-11-05 | `verify_sprint1.sh` |
| No `*.tfvars` tracked other than the example | `git ls-files` | Pass | 2026-11-05 | `verify_sprint1.sh` |

### Ticket 1.3: platform add-ons by Argo CD

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| Every Argo CD Application Synced and Healthy | `kubectl get applications -n argocd` | Pass: 28 of 28 | 2026-11-05 | `verify_sprint1.sh`, Jenkins builds #4–#6 |
| Each Postgres cluster archives WAL, and a base backup exists in Garage | `ContinuousArchiving` condition; `kubectl get backups.postgresql.cnpg.io -A` | Pass: archiving True in `sv-dev` and `sv-prod`; 9 completed scheduled backups across `sv-dev`, `sv-prod` and `keycloak` | 2026-11-05 | `verify_sprint1.sh`; Sprint 1 retro, Ticket 1.6 |
| Backup restores (spike) | Base backup, WAL archive and `bootstrap.recovery` into a new cluster on `sv-spike` | Pass: all rows, databases and roles back | 2026-11-02 | `spikes.md` T022 |
| A platform Deployment deleted by hand is put back by Argo CD (once) | `kubectl -n traefik delete deployment traefik` | Pass: recreated in 0.6 s, HTTPS back in 1.4 s | 2026-11-03 | `spikes.md`, drift check; infra #15 |
| Observability round trip (spike) | One trace, log and metric over OTLP, read back from Tempo, Loki and Prometheus | Pass | 2026-11-03 | `spikes.md` T019, T020 |
| Keycloak realms import once and are never overwritten (spike) | Restart after first import; client-credentials tokens; wrong secret | Pass | 2026-11-03 | `spikes.md` T025, T109 |

### Ticket 1.4: policy at admission and in CI

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `kubectl apply --dry-run=server` rejects every `tests/policy/bad/` file and accepts `good/` | Server-side dry runs against the lab | Pass: 6 rejected, 3 accepted | 2026-11-03, rechecked 2026-11-05 | `spikes.md` T026; `verify_sprint1.sh` |
| A PR adding a bad manifest under a service overlay fails its policy check | Throwaway gitops PR pointing the dev BFF overlay at `docker.io/library/nginx:1.29` | Pass: the `policy` job failed with "Images must come from ghcr.io/rclaye/; not allowed: docker.io/library/nginx:1.29"; PR closed unmerged, branch deleted | 2026-11-05 | gitops #21 (closed) |

### Ticket 1.5: service template and the delivery path

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| A merged BFF change runs in `sv-dev` with no manual step | App merge, build, GHCR, `sv-deployer` opens the gitops PR, auto-merge, Argo CD sync | Pass: `/healthz` 200, 401 without a token | 2026-11-05 | app #3, gitops #16 |
| The promotion PR cannot merge without the `prod` approval; prod then runs the same tag | Promote workflow, approval in the `prod` environment | Pass: `bff-prod` 2/2 on the dev tag | 2026-11-05 | gitops #17 |
| `git revert` of the promotion returns prod to its previous state | Revert PR through the same gate | Pass; re-promoted afterwards | 2026-11-05 | gitops #18, #19; infra #18 |

### Ticket 1.6: working sessions

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `make down` then `make up` returns every app to Healthy in under 10 minutes | Timed over SSH as `bot` | Pass: down 3 min 59 s, up 75 s to 28 apps healthy | 2026-11-05 | Sprint 1 retro |
| Grafana history from before the stop is still there | Prometheus `count(up)` range query across the stop | Pass: samples back to 22:45 UTC readable after `make up` | 2026-11-05 | Sprint 1 retro |
| `make down` changes nothing: only scheduled backups, no app out of sync | Backup list before and after; Argo CD status | Pass: the same 9 backups; 28 Synced | 2026-11-05 | Sprint 1 retro |

### Ticket 1.7: Jenkins and SonarQube Cloud

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| Jenkins listens on `127.0.0.1:8080` only, as the workstation's Jenkins account, and answers | `netstat` and `ps` (no sudo) from the workstation | Pass | 2026-11-05 | `verify_sprint1.sh` (workstation mode) |
| The everyday account cannot read the agent key; the workstation's Jenkins account is not an admin | File read test; `dsmemberutil` | Pass | 2026-11-05 | `verify_sprint1.sh` (workstation mode) |
| Exactly one job, `infra-terraform`, building `main` only | Defined in `jenkins/casc.yaml`; UI shows the one job | Pass | 2026-11-05 | `casc.yaml`; Jenkins UI |
| The `lab-host` agent runs as `bot` (not an admin) and a run shows plan, a paused approval and apply | A `terraform_data` record gave the pipeline a harmless change | Pass: `1 to add`, paused, approved by Richard, applied, `verify` green | 2026-11-05 | infra #25; build #6 |
| A PR to `sorted-vintage-app` shows the SonarQube Cloud quality gate | PR check and bot comment; SonarQube Cloud API | Pass: "Quality Gate passed" | 2026-11-05 | app #4; `verify_sprint1.sh` |
| Every Jenkins build checks the live lab (T107) | `verify` stage running the sprint's script with `MINI=local` | Pass | 2026-11-05 | infra #23; builds #4–#6 |

### Ticket 1.8: verify and measure

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `verify_sprint1.sh` passes | From the workstation, and on the lab host as the Jenkins `verify` stage | Pass | 2026-11-05 | infra #23; builds #4–#6 |
| The retro records measured memory by component next to the plan | Prometheus working sets now and over 24 h | Pass: 6.16 GiB of pods against the plan's 9.5 GB | 2026-11-05 | Sprint 1 retro |

## Sprint 2

### Ticket 2.1: retire the sprint's risks first

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `spikes.md` records the redirect result, the JVM memory and flags, the token decision, browser-free onboarding, the keycloak-config-cli result and the Keycloak check | Each spike run and written up | Pass, except the registration email to Mailpit (Open, above) | 2026-11-05 | infra #31, `sprints/sprint-2/spikes.md` |
| No change to the lab cluster beyond reads; spikes run on `sv-spike`, deleted afterwards | Spikes on `sv-spike` only; live Keycloak read with kcadm; `kind get clusters` afterwards | Pass: only `sorted-vintage` left | 2026-11-06 | `spikes.md` |

### Ticket 2.2: Java in CI, the BFF Ingress and Keycloak from Git

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| A PR adding a Gradle service shows build, Trivy and the SonarQube Cloud quality gate; after merge its dev tag reaches gitops with no manual step | The Listings PRs, the first Gradle service | Pass: build, image start check, Trivy and quality gate green on app #7; the dev tag PRs (gitops #28, #29) opened and auto-merged | 2026-11-07 | app #5, #6, #7; gitops #28, #29 |
| `https://dev.sortedvtg.lan:8443/healthz` answers 200 from the workstation's browser through the tunnel | Richard in the workstation's browser; also curl through the tunnel with the mkcert CA, dev and prod | Pass: `{"status":"ok"}`; certificate `*.sortedvtg.lan` verified | 2026-11-06 | gitops #22 |
| `infra-terraform` stays green with `sprints/sprint-2/` present and no `verify_sprint2.sh` | Jenkins builds after the Sprint 2 folder landed | Pass: `verify` chose `verify_sprint1.sh` and passed | 2026-11-07 | Jenkins builds on `f884254` and `5e65fc0` |
| A client setting changed in a realm file reaches the live `sv-dev` realm after one sync, with no admin-console edit | Added the `seed` client to `sv-dev.json`; Argo CD synced `keycloak`, the PostSync Job ran; checked with kcadm | Pass: `seed` present with only `view-users` and `manage-users`, secret equal to the Terraform value, `sv-prod` and other clients unchanged; Job took 28 s | 2026-11-07 | gitops #24 (Job: #22; secrets: infra #33); spike runs 2 and 3 in `spikes.md` |

### Ticket 2.3: Listings service and its data

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `listings-dev` and `listings-prod` are Synced and Healthy; `/healthz` answers in both namespaces; Flyway reports V1 applied | Argo CD status; `/healthz` through the API server proxy; `flyway_schema_history` in each `listings` database | Pass: 1 pod each, 0 restarts; `{"status":"UP"}`; `1 listings true` in dev and prod | 2026-11-07 | gitops #26, #29, #31, #32 |
| Its metrics appear in Prometheus and a request's trace in Tempo | Prometheus `up` and `jvm_memory_used_bytes` for the `listings` Service; Tempo search `service.name=listings` | Pass (dev): target up, JVM metrics present; traces found | 2026-11-07 | gitops #33 (Tempo fixed first) |

### Ticket 2.4: Listings features: drafts, photos, search, seller profile

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| T033 passes in CI, with the SonarQube Cloud gate green | App CI `build listings` (`./gradlew build`: contract tests on Testcontainers Postgres and Garage); SonarQube Cloud on the pull request | Pass: 48 tests pass, 5 publish tests skipped until T046; quality gate passed with 0 new issues, 0 hotspots and 0 dependency risks | 2026-11-10 | app #9 |
| A `.txt` renamed to `.jpg` gets 415 `photo_type_rejected` and an 11 MB image 413 `photo_too_large`; neither leaves an object in Garage | `ListingsContractTest` (`textRenamedToJpgIs415AndLeavesNothingBehind`, `elevenMegabytesIs413AndLeavesNothingBehind`), which list the bucket and count photo rows after each upload; run on the lab host and in CI | Pass: 415 and 413 with the contract's body; no object under the listing's prefix and no photo row | 2026-11-10 | app #9 |
| The new Listings runs in `sv-dev` and its public routes answer as the contract says | Argo CD status after the dev-tag PR; requests through a port-forward to the `listings` Service | Pass: Synced and Healthy, 0 restarts, no warning or error logs; `GET /listings` 200 `{"items":[],"next_cursor":null}`; `limit=61` and an unknown category 422; an unknown listing or seller 404; `POST /listings` without a token 401 | 2026-11-10 | app #9, gitops #34 |
| Create a listing and upload a photo in `sv-dev` | By hand in the workstation's browser through the BFF (Ticket 2.6 walkthrough) | Pass: draft "Stussy Shirt" created 01:57:58 UTC, photo stored in Garage 01:59:26 | 2026-11-11 | app #12, #14 |

### Ticket 2.5: Payments: onboarding and Connect events

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| T034 passes in CI, with the SonarQube Cloud gate green | App CI `build payments` (pytest with Testcontainers Postgres on Python 3.12); SonarQube Cloud project `rclaye_sv-payments` | Pass: 59 tests in #10, 62 in #11 (3 template `azp` tests skipped by design); gate passed with 0 new issues on its first scan | 2026-11-10 | app #10, #11 |
| A request with a bad `Stripe-Signature` gets 400 and stores nothing; a replayed event is a no-op | Requests to Payments in `sv-dev` through a port-forward on the lab host, signed there with the `stripe` Secret's value (never printed); inbox rows counted in the `payments` database | Pass: no signature and a wrong secret each 400 `invalid_signature`, 0 rows; a signed test event 200, its replay 200 `duplicate`, 1 row (`evt_verify_1794350442`, type `v1.verify.ping`) | 2026-11-10 | gitops #35, #36 |
| After test onboarding, payout status turns `ready` through the forwarder | Test seller 1 created with Payments' code in the dev sandbox; Stripe-hosted onboarding completed in the workstation's browser; forwarder logs and the `payment_event` inbox read on the lab host | Pass with a finding: 19 thin events forwarded, each 200, verified, stored once and applied; Stripe's account read still showed `restricted` after the last event, so `ready` came from the next reconciliation about 3.5 minutes later. Fixed in app #11 (a second read 10 seconds after an account event); two request bugs found here fixed in #11 too | 2026-11-10 | app #11, gitops #35 |
| With the forwarder stopped, payout status turns `ready` within 5 minutes through reconciliation | Dev forwarder at 0 replicas by gitops #38; test seller 2 created with app #11's code and onboarded in the browser; `connected_account` polled | Pass: 0 events received for the account; `ready` at 00:01:15 UTC, about 3.5 minutes after submitting; forwarder restarted by gitops #39 | 2026-11-11 | gitops #38, #39 |
| `POST /connected-accounts/me/onboarding-link` live in `sv-dev` | By hand through the BFF's "Set up payouts with Stripe" (Ticket 2.6 walkthrough) | Pass: Payments created the seller's account at 01:53:04 UTC and returned a hosted link the browser followed | 2026-11-11 | app #11, #14 |

### Ticket 2.6: Publish, sign-in and the pages

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| T046, T047 and T048 pass in CI, with the SonarQube Cloud gate green | App CI on each PR; SonarQube Cloud `rclaye_sv-listings` and `rclaye_sv-bff` | Pass: Listings 59 then 60 tests, BFF 62 tests; the BFF gate first failed on `pythonsecurity:S7044` (API traversal in the photo route), fixed by accepting only listing and photo UUIDs, then passed | 2026-11-11 | app #12, #13, #14 |
| Quickstart step 2 by hand in dev, with times (SC-001): onboarding under 5 minutes, publishing after onboarding under 2 minutes, the listing in browse within 5 seconds | Richard in the workstation's browser on `https://dev.sortedvtg.lan:8443`, with a stopwatch; server times from Keycloak, Payments, Listings and Mailpit | Pass: sign-up with the verification email in Mailpit (01:51:40 UTC), signed in 01:52:31; onboarding about 4 minutes by stopwatch (account created 01:53:04, `ready` 01:56:55, 4 seconds after Stripe's last events thanks to the second read from app #11); listing under 2 minutes by stopwatch (draft 01:57:58, published 01:59:33); in browse at once (published and available in one transaction) | 2026-11-11 | app #11, #12, #14; gitops #45, #46 |
| A registration email from the live `sv-dev` realm reaches Mailpit (open since Ticket 2.1) | The walkthrough's sign-up; Mailpit's API read on the lab host | Pass: "Verify email" received 01:51:40 UTC; the link signed the user in | 2026-11-11 | gitops #45 |
| Sign-in is safe against the usual mistakes | BFF tests: forged `state`, a token for another client, a replayed nonce, a tampered cookie, refresh and a refused refresh, CSRF on forms and logout, off-site `next`, HTML escaping, photo paths | Pass: all covered in `tests/test_signin.py` and `tests/test_pages.py`; Content-Security-Policy `'self'` only (form-action also Stripe), `X-Frame-Options: DENY`, checked live from the workstation | 2026-11-11 | app #14 |
| The timed check that a published listing is in browse within 5 seconds, automated (T113) | `verify_sprint2.sh` (Ticket 2.8 below) | Pass: automated in Ticket 2.8 | 2026-11-12 | infra #47 |

### Ticket 2.7: seed data

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| A pod can sign in through the BFF login form (spike) | Throwaway pod in `sv-dev`: names sent to Traefik's Service, a temporary user made with the `seed` client and deleted after | Pass: `/login` 303, Keycloak form 200, credentials 302, callback 303 to `/sell`, `/sell` 200 signed in; user deleted 204. TLS then trusted what Traefik served; the job pins the Terraform certificate instead | 2026-11-12 | [spikes.md](../sprints/sprint-2/spikes.md#in-cluster-sign-in-t051-t115), infra #45, #46 |
| Only the `seed` client may link a seller to a Stripe account, and only in dev | Payments tests; live: a `seed` token on `PUT /connected-accounts/{sub}` in dev | Pass: 15 new tests (404 unless `ACCOUNT_LINK_AZP` is set, 403 for other clients); live token carries `aud: payments`, the route answered 422 to an empty body (past 404 and 403) | 2026-11-12 | app #15, gitops #48 |
| After a sync, browse in dev shows 50 seeded listings | `seed-dev` synced; Job log; Listings search read from a pod | Pass: Job succeeded on its first try, demo sellers linked with payouts `ready`, verify seller created unlinked; search held 51 listings, the 50 seeded (`#01`–`#50`, 25 per demo seller) each with a photo, plus the walkthrough's | 2026-11-12 | app #16, gitops #52, infra #44, #46 |
| Running the hook again changes nothing | Seed tests: a second run only fills gaps; a seller already present is updated, not created | Pass in tests (13 tests, 87% coverage); a second run in the lab not yet seen | 2026-11-12 | app #16 |
| The verify seller is onboarded once by hand and its id kept out of Git | Richard on `/sell/onboarding` with Stripe's test values; id read from Payments' database and added to `seed_sellers` on the lab host | Pass: payouts `ready`, account `active`/`active`; Jenkins apply put it in Secret `seed-sellers` | 2026-11-12 | this log; `secrets.auto.tfvars` on the lab host |

### Ticket 2.8: verify and measure

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `verify_sprint2.sh` passes from the workstation, after `verify_sprint1.sh` | Run from the workstation, twice | Pass: 72 checks, Sprint 1 and Sprint 2; one skip (`/webhooks/stripe` is Sprint 3) | 2026-11-12 | infra #47 |
| Bad Stripe signatures refused | Unsigned POST to Payments `/webhooks/stripe-connect` through the API server, `sv-dev` and `sv-prod` | Pass: 400 in both | 2026-11-12 | infra #47 |
| A scripted listing by the verify seller is in search within 5 seconds, then deleted; bad photo type and size refused (T113) | `verify_selling.sh` on the lab host: sign-in through the BFF form, renamed `.txt`, 11 MB image, two photos, publish, search polled every 0.25 s, delete | Pass: 415 `photo_type_rejected`, 413 `photo_too_large`; in search 0.05 s after publishing; after delete 404 and gone from search | 2026-11-12 | infra #47, app #17 |
| The Jenkins `verify` stage runs Sprint 2's checks, read-only | `infra-terraform` build after infra #47 (apply of `seed-sellers`, then verify with `MINI=local`) | Pass as reported by Richard; the build page needs a sign-in, so it was not read from here | 2026-11-12 | Jenkins `infra-terraform` |
| Memory re-measured with the services running (T119) | Prometheus working sets through the API server proxy, as T032; `docker stats`; `memory_pressure` | Pass: pods 8.29 GiB (24 h median 7.96, p95 8.37, peak 8.81), node 9.28 of 11.91 GiB, lab host 55% free | 2026-11-12 | [sprint2_retro.md](../sprints/sprint-2/sprint2_retro.md#memory-measured-again-t119) |
