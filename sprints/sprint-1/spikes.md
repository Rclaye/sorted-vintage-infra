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
