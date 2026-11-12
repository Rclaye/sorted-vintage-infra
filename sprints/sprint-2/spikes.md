# Sprint 2 spikes

Results of the spikes in Ticket 2.1, run on 2026-11-05 on the lab host as `bot` and from the workstation's browser. Each entry says what was done, the result and what it changes. Throwaway clusters were named `sv-spike` and deleted afterwards; the lab cluster was only read, and the Stripe work stayed in the dev sandbox.

## Live Keycloak check (read-only)

**Result: pass.** With `kcadm.sh` inside `keycloak-0` against the live realms:

| Check | Result |
| --- | --- |
| `bff` redirect URIs, dev | `https://dev.sortedvtg.lan/*` and `https://dev.sortedvtg.lan:8443/*`, so `/auth/callback` is covered; prod the same with `prod.` |
| `bff` client | Confidential, authorization-code flow on, direct-access grants **off** |
| Sign-up | `registrationAllowed`, `verifyEmail` and `loginWithEmailAllowed` on in both realms |
| SMTP | `mailpit.sv-<env>.svc.cluster.local:1025`, the same as the realm files in Git |

- `kcadm.sh get realms/<r> --fields smtpServer` prints `{}` for nested objects. Read the realm unfiltered, or use `smtpServer(*)`.
- Not proven yet: a verification email arriving in Mailpit. That needs one real sign-up, which comes with the first BFF login (T047).

## JVM memory (T035)

**Result: pass.** A minimal Spring Boot web app with Actuator, Java 21, the OpenTelemetry Java agent 2.33.1 (exporters off) in `eclipse-temurin:21-jre`, built for `linux/arm64`, run non-root on `sv-spike` under a 512 Mi limit. Image 390 MB, jar 22 MB.

| Variant | Startup | Ready | Idle | After 500 requests | Restarts |
| --- | --- | --- | --- | --- | --- |
| A: G1, `-XX:MaxRAMPercentage=75` | 3.6 s | 8 s | 230 MiB | 241 MiB | 0 |
| B: SerialGC, `-XX:MaxRAMPercentage=60 -Xss512k` | 3.4 s | 8 s | 274 MiB | 274 MiB | 0 |

- **Decision for T035:** variant A, the default collector with `-XX:MaxRAMPercentage=75`, a memory limit of 512 Mi and a request of about 320 Mi. The real Listings service adds JPA, Flyway and security, so expect 350–400 MiB, inside the 0.4 GB budget; measure again once it exists (T119).
- The pod passed the Kyverno rules for non-root, requests and limits and host paths. It failed `restrict-image-registry` only, as it should for a locally built image.
- **Decided 2026-11-06: Spring Boot 4** (research R21). This spike was already built on Boot 4.1.2, the Spring Initializr default, so the numbers above apply as they stand.
- The lab used 6.6 of 11.9 GiB during the spike, so the extra cluster fitted.

## Browser-free Stripe onboarding (T043, T051, T115)

**Result: not possible; one hosted-page visit is needed.** Dev sandbox, Stripe CLI 1.55.6, a test v2 account created with the research R17 settings (`dashboard: none`, fees `application`, losses `stripe`, merchant and recipient configurations).

- Both capabilities start `restricted`. `stripe_transfers` needs only the terms-of-service attestation; `card_payments` needs the full profile (identity, address, date of birth, SSN, phone, MCC, statement descriptor, business URL, product description). `external_account` gates payouts only, not `ready`.
- **Blocker:** setting `identity.attestations.terms_of_service.account` through the API is refused with "You cannot accept the Terms of Service on behalf of accounts where requirement collection is owned by Stripe". That is our setup, where Stripe is the losses collector.
- Everything else prefills through the API. Test values that worked: `+10000000000` as the phone (`+15555550100` was refused), date of birth 1901-01-01, address line `address_full_match` in San Francisco, CA 94111, MCC 5931, business URL `https://accessible.stripe.com`. After prefill Stripe still asked for the full test SSN `000000000` and a statement descriptor.
- The CLI prints a "Running in <sandbox>" line before the JSON; drop line 1 before `jq`. v2 `GET` takes `?include=` in the path, and closing an account needs `{"applied_configurations":["merchant","recipient"]}`.

**What it changes:** the seed job (T051) and the verify seller (T115) cannot be made `ready` without a browser. Each seller is onboarded **once by hand** in the dev sandbox, and its Stripe account then stays ready, so the seed job links a seller to an existing account instead of creating one. T051 and T115 say so.

## Onboarding redirect (T052, research R6)

**Result: pass.** Richard completed Stripe's hosted onboarding in the workstation's browser, through the SSH tunnel on port 8443, for a prefilled test account.

- The Account Link accepted `https://dev.sortedvtg.lan:8443/sell/onboarding` as `return_url` and `?refresh=1` as `refresh_url`. The browser landed on `https://dev.sortedvtg.lan:8443/sell/onboarding` and Traefik answered 404, because the BFF has no page there yet. So the `localhost` fallback is not needed, and T043 uses `https://<env>.sortedvtg.lan:8443/sell/onboarding`. A URL without the port does not reach the lab from the workstation.
- Afterwards `card_payments` and `stripe_transfers` were both `active` with no requirements left: payout status `ready`.
- Steps on the hosted page, with the details prefilled: payout bank (a Stripe Link popup appears: choose "Finish without saving"; the test account ending 6789 succeeds, 2227, 1113, 1116 and 3335 simulate failures), public details, review, "Agree and submit". About five minutes by hand, inside SC-001's five-minute target.
- **Statement descriptor:** the API accepted `SORTED VINTAGE`, but the hosted page rejected it: it must resemble the business URL or legal name (`ACCESSIBLE` passed). T043 and T051 derive the descriptor from the seller's name or business URL, never a fixed brand string.
- The support address needs `address_full_match` in test mode, and the business name is optional.
- The test account was closed afterwards.

## keycloak-config-cli (T120)

**Result: pass.** Keycloak 26.8.1 in `start-dev` on `sv-spike` with the `sv-dev` realm file from gitops, then `adorsys/keycloak-config-cli:6.5.1-26.5.5` as a Kubernetes Job. A user "alice" was created through the admin API first, standing in for a sign-up.

| Step | `bff` redirect URIs | alice | Clients | SMTP |
| --- | --- | --- | --- | --- |
| Before | 2 | present | 10 | Mailpit |
| Run 1, file unchanged | 2 | present | 10 | unchanged |
| Run 2, file adds a redirect URI | 3, new one applied | present | 10 | unchanged |
| Run 3, same file again | 3, no change | present | 10 | unchanged |

- The realm files' `${SV_DEV_*_SECRET}` placeholders work unchanged with `IMPORT_VARSUBSTITUTION_ENABLED=true`, prefix `${` and suffix `}`, reading the same Secret.
- The newest published build (made for Keycloak 26.5) works against 26.8.1. Pin the image and check it when Keycloak is upgraded.
- After a restart alice was gone: dev mode keeps its database in the pod. The lab's Keycloak uses Postgres, so that does not apply there.
- T120 can go ahead as planned. Realm files in Git stay the record of the realm; users are never in them.

**Second run, 2026-11-06: pass with the lab's setup.** The committed Job (gitops `platform/keycloak/realms/config-cli-job.yaml`, rendered by kustomize as Argo CD does) against Keycloak installed like the lab: keycloakx chart 7.4.0 with the lab's values, `kc.sh start`, `KC_HOSTNAME=https://auth.sortedvtg.lan:8443`, backchannel dynamic, `xforwarded` proxy, Postgres.

| Step | `bff` redirect URIs | alice | Clients | `bff` secret |
| --- | --- | --- | --- | --- |
| Before (start-up import) | 2 | present | 10 | equals the Secret |
| Run 1, file unchanged | 2 | present | 10 | equals the Secret |
| Run 2, file adds a redirect URI | 3, new one applied | present | 10 | equals the Secret |
| Run 3, same file again | 3, no change | present | 10 | equals the Secret |

- The Job reaches the admin API on the in-cluster URL `http://keycloak-http.keycloak.svc.cluster.local` although the hostname is the external one; each run took 2 to 5 seconds of import.
- It runs as UID 1001, non-root, with a read-only root filesystem and only `/tmp` writable, inside a 512 Mi limit.
- Lesson from a false failure on the way: Keycloak creates its bootstrap admin once, in the database. Replacing the `keycloak-admin` Secret afterwards does not change the admin's password, so the Job would fail with "Invalid user credentials" while waiting for Keycloak. Rotate the admin password in Keycloak and the Secret together.

## Script token (T051, T115)

**Decision: scripts log in through the BFF's login form**, as one dedicated `sv-dev` verify seller, like a browser would. No direct-access-grants client is created. The verify seller's password is generated into `secrets.auto.tfvars` and reaches `sv-dev` as a Terraform Secret, and the seed job creates users through a `sv-dev` client limited to user management (both declared through T120). Recorded because it keeps Keycloak's client settings unchanged and exercises the real sign-in path, at the cost of a little more scripting (cookies and form fields).

**Third run, 2026-11-06: the `sv-dev` seed client, pass.** Same lab-like Keycloak on `sv-spike`, realm loaded from today's `sv-dev.json`, a user created first; then the Job applied `sv-dev.json` with a `seed` client (confidential, service account only, secret `${SV_DEV_SEED_SECRET}`) and its service-account user holding `realm-management` `view-users` and `manage-users`.

| Check | Result |
| --- | --- |
| `seed` client created, other 10 clients unchanged | yes |
| Its secret equals `SV_DEV_SEED_SECRET` in `keycloak-realm-clients` | yes |
| Effective roles | `manage-users`, `view-users`, `query-users`, `query-groups` |
| Its own token: create a user in `sv-dev` | 201 |
| Its own token: list `sv-dev` clients / read `sv-prod` users | 403 / 403 |
| Existing user kept through every run; same file again changes nothing | yes |

- Terraform must create `SV_DEV_SEED_SECRET` before the realm file refers to it, so the infra change is applied first.

## In-cluster sign-in (T051, T115)

**2026-11-12, pass, in the lab's `sv-dev`.** The question: can a pod drive the BFF login form, when the browser's addresses (`https://auth.sortedvtg.lan:8443`, `https://dev.sortedvtg.lan:8443`) only exist on the workstation through the SSH tunnel? A throwaway pod ran the BFF image already on the node (no pull), with `hostAliases` pointing both names at Traefik's ClusterIP and the script changing port 8443 to 443. The names stay the same, so Keycloak's fixed issuer, the BFF's `PUBLIC_BASE_URL` redirect and the cookies all match what a browser sees. A temporary user `spike-signin` was created with the `seed` client and deleted at the end (in a `finally`, so also on failure).

| Step | Result |
| --- | --- |
| `seed` token on the in-cluster URL (client credentials) | 200 |
| Create the temporary user | 201 |
| `GET dev…/login` | 303 to Keycloak's authorize URL |
| `GET auth…/openid-connect/auth` | 200, login form, action on `auth.sortedvtg.lan:8443` |
| `POST …/login-actions/authenticate` | 302 to `dev…/auth/callback` |
| `GET dev…/auth/callback` | 303 to `/sell` (the `next` path; a failure goes to `/`) |
| `GET dev…/sell` | 200, signed in, `sv_session` cookie held |
| Delete the temporary user | 204 |

- TLS was verified with hostname checking on: the pod trusted the certificate Traefik serves (OpenSSL partial-chain), so no mkcert root goes into the cluster or the repos.
- Kyverno's `require-resources` refuses a pod without CPU and memory requests and limits; the seed Job needs both.
- `sv-dev` has no NetworkPolicy, so the pod reached Traefik and `keycloak-http` without changes.
- For the seed job: sign each seller in this way, then create listings through the BFF's selling pages (the access token stays inside the encrypted session cookie). Label its pods `lab-live=true` so the workstation's live pane follows them.
