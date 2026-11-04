# Sprint 1 spikes

Results of the spikes in Ticket 1.1 and the later tickets that record findings here. Each entry lists the commands, the result and what it changes.

## T008: Kind survives stop and start (research R1)

**Result: pass.** 2026-11-01, Mac mini M4, as `bot`. Kind v0.33.0, node image `kindest/node:v1.37.0`, Docker Desktop engine 29.7.2 with 12 GB.

What it did:

1. Created a one-node cluster: `kind create cluster --name sv-spike --wait 180s`. It was ready in 24 seconds, 16 of them waiting for the control plane.
2. Applied a 64 Mi `PersistentVolumeClaim` on the default `standard` class, and a `busybox:1.37` pod that writes the time to `/data/first` once and appends a line to `/data/boots` on every start.
3. Ran `docker stop sv-spike-control-plane`, then `docker start sv-spike-control-plane`.
4. Waited for `/readyz`, the node and the pod, then read the files again.
5. Deleted the cluster.

| Check | Result |
| --- | --- |
| API server back after `docker start` | 4 s |
| Pod `Ready` again | 5 s, one container restart |
| `/data/first` | unchanged (`Mon Nov  2 02:27:43 UTC 2026`) |
| `/data/boots` | two lines, so the container ran again on the same volume |
| Pods not `Running` afterwards | 0 of 10 |

What it means: a single-node Kind cluster can be stopped between sessions and started again with its data, so research R1 stands and Ticket 1.2 can go ahead. This cluster was nearly empty. `make up` still has to show that the full platform returns in under 10 minutes (Ticket 1.6).

### Finding: image pulls over SSH need the keychain

The first attempt failed before creating anything. Docker Desktop could not pull `kindest/node` from an SSH session:

```text
keychain cannot be accessed because the current session does not allow user interaction
```

An empty client config (`DOCKER_CONFIG` holding `{}`) and `bot`'s own socket (`DOCKER_HOST=unix://$HOME/.docker/run/docker.sock`) failed the same way, so the keychain lookup comes from Docker Desktop's backend, not the `docker` command. `bot` has no registry logins (`"auths": {}`).

- **Workaround used:** one `docker pull` of the node image in a Terminal in `bot`'s desktop session at the mini. After that, the SSH run passed.
- **Not affected:** the images the cluster runs are pulled by containerd inside the Kind node, not by Docker Desktop.
- **Open, for Ticket 1.7:** the Jenkins agent logs in over SSH, so `make rebuild` will fail the same way whenever the Kind version changes and the new node image isn't cached yet. Options to test there: the keychain "Always Allow" for `bot`, Docker Desktop's credential settings, or pre-pulling the node image as a documented step of a Kind upgrade.

## T009: Stripe signing secrets (research R3, R4)

**Result: pass, with a design change (research R17).** One signing secret per sandbox covers platform events and connected-account events. Connected accounts move to Accounts v2. 2026-11-01, as `bot`, Stripe CLI 1.55.6, API version `2026-10-28.endive`.

Setup: sandboxes `sorted-vintage-dev` and `sorted-vintage-prod`, both with Connect enabled. The CLI is logged in to each as `bot`, with projects `sv-dev` and `sv-prod`; its config is `600`. No key or signing secret was printed: a small receiver read the secret from a `600` file and logged only whether each signature verified.

| Question | Answer |
| --- | --- |
| Do dev and prod get different signing secrets? | Yes. The sandboxes' secrets differ (compared by hash), which matches R3. |
| Is the secret stable across `stripe listen` sessions for one sandbox? | Yes. `--print-secret` and a running `listen` session showed the same secret. |
| Is a platform event signed with that secret? | Yes. A confirmed test PaymentIntent (`pm_card_visa`) arrived on `--forward-to` as `payment_intent.succeeded`, `account=platform`, signature valid. |
| Are connected-account events signed with the same secret? | Yes. With a v2 account, `v1.account.updated` and `v1.capability.updated` arrived as thin events and every signature verified (below). |

Commands, for the record (keys stay in the CLI's config):

```bash
stripe listen --project-name sv-dev --events payment_intent.succeeded --forward-to 127.0.0.1:4242/platform --forward-connect-to 127.0.0.1:4242/connect
stripe payment_intents create --project-name sv-dev --amount 1500 --currency usd --confirm true --payment-method pm_card_visa -d "automatic_payment_methods[enabled]=true" -d "automatic_payment_methods[allow_redirects]=never"
```

### Findings

- **Accounts v1 creation is off in new sandboxes.** `stripe trigger account.updated` fails: `POST /v1/accounts` returns 400, and Stripe says to create connected accounts with `POST /v2/core/accounts` (Accounts v2), or to enable "Accounts v1 support" in the Dashboard under Developers → API policies. Research R6 and tasks T043–T045 assume Express accounts created through v1, with `account.updated` on the Connect stream. This needs a decision before Sprint 2's onboarding work.
### Accounts v2 run

After the decision to move to Accounts v2, the same receiver ran against two `stripe listen` sessions on `sv-dev`: one for platform snapshot events (`--events payment_intent.succeeded,payment_intent.payment_failed`) and one for connected-account thin events (`--all-thin --events-from @accounts`). Both sessions used the sandbox's one signing secret.

| Step | Result |
| --- | --- |
| Create an account with the Express dashboard | Refused for every fee and setup combination. Express needs the platform as losses collector, and this platform cannot be (`account_creation_losses_collector_unavailable`). With Stripe as losses collector, only `dashboard: none` or `full` is accepted, and only with the `merchant` configuration. |
| Create `dashboard: none`, fees `application`, losses `stripe`, configurations `merchant` (card payments) and `recipient` (Stripe transfers) | Created. Both capabilities `restricted`, 15 requirement entries until onboarding. |
| Stripe-hosted onboarding link (`POST /v2/core/account_links`, `use_case.type: account_onboarding`) | Created on `connect.stripe.com` with return and refresh URLs on `https://dev.sortedvtg.lan/sell/onboarding`, and also on `https://localhost:8443/sell/onboarding`. The browser redirect itself is still T052. |
| Update the account | Thin events `v1.account.updated` and `v1.capability.updated` reached `/thin`, `from=connected`, all signatures valid. |
| Destination charge before onboarding | Refused: the destination needs the `recipient` configuration's transfers active. Matches FR-014: no sales before onboarding. |
| Clean-up | Every test account closed. |

Command details, because the CLI's v2 syntax is not obvious:

- `stripe v2 core accounts create` takes dotted flags (`--dashboard none`, `--defaults.responsibilities.losses-collector stripe`, `--configuration.recipient.capabilities.stripe-balance.stripe-transfers.requested=true`).
- Account Links need a JSON body: `stripe post /v2/core/account_links -d '{"account":"acct_…","use_case":{"type":"account_onboarding","account_onboarding":{"return_url":"…","refresh_url":"…"}}}'`. A `configurations` field there is rejected as unknown.

- **`payment_method_types` is no longer accepted.** `stripe trigger payment_intent.succeeded` fails because its fixture sends it. PaymentIntents use `automatic_payment_methods`, with payment methods chosen in the Dashboard. T066 and the traffic generator (R6) must not send `payment_method_types`.
- **`stripe listen` needs the events named** (`--events`, `--all-snapshot` or `--all-thin`). The R4 Deployment must pass `--events` with the list Payments handles.
- **`localhost` resolves to `::1` first** for the CLI's forwarder. Forward to `127.0.0.1` or a Service name, never `localhost`.
- **The mini's firewall drops loopback connections to apps not on its allow list.** Homebrew's Python was dropped even on `127.0.0.1`; `/usr/bin/python3` is allowed. This affects only processes on macOS; the forwarder will run inside the cluster.

## T022: CloudNativePG backup and restore against Garage (research R19)

**Result: pass.** 2026-11-02, on a throwaway Kind cluster `sv-spike` on the mini, as `bot`, with the same manifests and chart versions as `sorted-vintage-gitops/platform/garage` and `platform/postgres`: Garage v2.5.0, cert-manager v1.21.3, CloudNativePG chart 0.29.1 (operator 1.30.1), Barman Cloud Plugin chart 0.8.1 (v0.15.1). The cluster was deleted afterwards.

### Garage and its setup Job

| Check | Result |
| --- | --- |
| Setup Job, first run | Applied the one-node layout, imported both S3 keys, created `photos` and `backups`, granted each key its bucket |
| Setup Job, second run | Changed nothing: every step reported `present`, and re-granting is harmless |
| Garage restart | Both buckets still there, read back from the host path `/var/lab-data/garage-dev` |

Finding: Garage's `/health` passes only once a layout exists, and the layout is applied by the setup Job, which needs the pod Ready first. An HTTP readiness probe on `/health` deadlocks, in a plain cluster and in Argo CD alike (PostSync hooks wait for a Healthy StatefulSet). The readiness probe is a TCP check on the admin port; the Job owns layout health.

### Postgres backup and restore

| Check | Result |
| --- | --- |
| Cluster `pg` with the plugin as WAL archiver | `Ready`, `ContinuousArchiving=True` |
| `Database` resources `orders`, `payments`, `notifications` and managed roles | Created, `applied: true` |
| Immediate base backup from the `ScheduledBackup` | `completed`, method `plugin` |
| WAL reaching Garage after a write | About 60 s, in line with `archive_timeout: 60s` |
| Restore into a new cluster with `bootstrap.recovery` from the same `ObjectStore` | All 3 rows (one from the base backup, two from archived WAL only), all 4 databases and all 4 roles |

The first restore attempt started 40 s after the last write and correctly stopped at the last WAL segment then in Garage; it was retried once that segment had been archived. Restoring right after a write needs the archive to catch up first, which `make down`'s check already provides (research R14).

### Findings for later tasks

- **Last archived WAL time (needed by T013).** The `ObjectStore` status has only the recovery window (`serverRecoveryWindow.<cluster>.firstRecoverabilityPoint`, `lastSuccessfulBackupTime`); the `Cluster` status has the `ContinuousArchiving` condition but no archive time. The time comes from Postgres: `select last_archived_wal, last_archived_time, failed_count from pg_stat_archiver` on the primary. `make down` checks that condition and that `last_archived_time` is under 120 s old.
- **Recovery creates an extra `app` database** unless told otherwise. The recovery overlay in T076 sets `bootstrap.recovery.database: listings` and `owner: listings`.
- **StatefulSets do not replace a pod that never became Ready**, so a fix to a broken readiness probe needs that pod deleted once. Not an issue on a fresh install.

## T108: Ownership on the `/var/lab-data` mount

**Result: no root step needed.** 2026-11-03, on the lab cluster's node container, as `bot`.

Docker Desktop shares `~/sv-data` into the Kind node through `virtiofs`. Inside the node, `/var/lab-data/garage-dev` shows as `uid=0 mode=755`, yet a fresh directory there accepted writes from uid 1000 and from an arbitrary uid 4242 without any `chown`, and on the Mac every file lands owned by `bot` (uid 502) whatever uid wrote it. The mount does not enforce ownership.

- The Garage `own-data` init container, which ran as root to `chown` the path, is removed; Garage runs as uid 1000 and creates `meta/` and `data/` itself.
- The flip side: any pod that mounts `/var/lab-data` can write all of it. The control is admission: only Garage's PersistentVolumes may use `hostPath` (added to T026).
- This holds for Docker Desktop on macOS. On a Linux host, a bind mount enforces ownership, and the folders would need creating with uid 1000 as owner.

## T019, T020: Observability round trip and memory

**Result: pass.** 2026-11-03, on a throwaway Kind cluster `sv-spike`, as `bot`, with the exact values in `sorted-vintage-gitops/platform/observability`: kube-prometheus-stack 92.17.0, Loki 7.5.0 (single binary), Tempo 1.24.4, OpenTelemetry Collector 0.178.1 (contrib image). The cluster was deleted afterwards.

| Check | Result |
| --- | --- |
| All four charts install and every pod runs | Yes, 9 pods |
| OTLP over HTTP into the collector: one trace, one log, one metric | All 200 |
| Metric read back from Prometheus (OTLP receiver) | `spike_requests_total` |
| Log read back from Loki by `service_name` | Found |
| Trace read back from Tempo by `service.name` | Found |
| Grafana's admin password | From the Terraform Secret `grafana-admin`, not the chart default |
| Memory added by the stack | About 2.1 GiB (0.62 to 2.68 GiB), within the plan's 2.3 GB |

On the lab that puts the cluster at about 6.0 of 11.9 GiB after Ticket 1.3's part 5.

Finding: Argo CD's metrics Service is labelled `app.kubernetes.io/name: argocd-metrics`, not `argocd-application-controller`; the ServiceMonitor for the drift alerts (T111) selects on that label.

## T025, T109: Keycloak realms, tokens and re-import

**Result: pass.** 2026-11-03, on a throwaway Kind cluster `sv-spike`, as `bot`, with the exact values and realm files in `sorted-vintage-gitops/platform/keycloak`: keycloakx chart 7.4.0 (Keycloak 26.8.1) on a CloudNativePG `keycloak-db` (WAL archiving was left out here; it was proven in T022). The cluster was deleted afterwards.

| Check | Result |
| --- | --- |
| First start | Realms `sv-dev` and `sv-prod` imported |
| Restart | "Realm 'sv-dev' already exists. Import skipped", and the same for `sv-prod`: a restored database is never overwritten (R16) |
| Client-credentials tokens, both realms | `orders` gets audiences `listings`, `payments`; `payments` gets `orders`; `listings` gets `payments` (R13) |
| Wrong client secret | Refused with 401 |
| `bff` | Confidential, code flow, PKCE S256, redirects to `https://<env>.sortedvtg.lan[:8443]/*`, mappers `display_name` and three audiences |
| Realm settings | Registration with email verification through that environment's Mailpit; `display_name` required, 1 to 40 characters |
| Token issuer | `https://auth.sortedvtg.lan:8443/realms/sv-<env>` |
| Memory added | About 1 GiB for Keycloak and `keycloak-db` |

Findings:
- Because a realm is imported only once, a mistake in a realm file would have to be fixed in the live realm. The spike is the check that the files are right before the lab imports them.
- Tokens also carry the default `account` audience from Keycloak's built-in roles scope; services check for their own audience and ignore it.
- The issuer includes `:8443`, the SSH tunnel's port. When Tailscale replaces the tunnel (R2), `KC_HOSTNAME` changes with it, and so does the issuer the services expect.
