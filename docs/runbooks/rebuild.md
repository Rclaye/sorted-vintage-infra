# Rebuild the Lab From Git (T078)

How to destroy the lab and bring it back from the three repos, with or without its data. Proven on `sv-spike` before the lab ([sprints/sprint-4/spikes.md](../../sprints/sprint-4/spikes.md)); the timed drill through Jenkins (T077) is below; T098 is running it.

Run everything on the lab host as `bot`, from `~/Sorted-Vintage/src/sorted-vintage-infra`, with the lab up (`make up`) unless a step says otherwise.

## What survives, what does not

| Survives a destroy | Why |
| --- | --- |
| Garage data in `~/sv-data` on the host: listing photos and the Postgres archives (base backups and WAL) | it is outside the cluster |
| Terraform state and `secrets.auto.tfvars` in `~/sv-terraform` | outside any clone |
| Database passwords, Stripe keys, the BFF, Orders, Payments and Listings client secrets, the TLS certificate | fixed values in `secrets.auto.tfvars`, so restored roles still match their Secrets |
| Stripe connected accounts and PaymentIntents | they live in Stripe's sandboxes |
| Everything in the three repos | Git |

| Lost by a destroy | What brings it back |
| --- | --- |
| The Kind cluster, every pod and volume | `make rebuild`, then Argo CD syncs from Git |
| Postgres data (sv-dev, sv-prod, Keycloak) | **only a restore** (below); without one, the databases start empty |
| Generated values: the `notifications` and `seed` client secrets, Grafana's admin password, the BFF cookie key (everyone signs in again), `verify-seller` and `verify-buyer` passwords | Terraform makes new ones; keycloak-config-cli writes the client secrets into the realms; the seed job resets the verify users' passwords |
| Metrics, logs and traces in Prometheus, Loki and Tempo | not kept; they start again |
| Mail in Mailpit, messages in RabbitMQ queues | not kept (an order's event already applied is in the databases) |

## Rebuild without data

```bash
make destroy
```

```bash
make rebuild
```

Both ask before applying. `make rebuild` waits until every Argo CD app is Synced and Healthy. The databases start empty in `initdb` mode; the seed job lists the demo listings again (and creates the users), so dev is usable but has no history.

## Rebuild with the data (a restore)

Each database cluster has a committed restore mode in gitops: `platform/postgres/overlays/dev/restore.yaml`, `platform/postgres/overlays/prod/restore.yaml` and `platform/keycloak/db/restore.yaml`. Normally each is in `initdb` mode and names the archive the cluster writes to (`serverName`, today `pg`, `pg` and `keycloak-db`). A restore recovers from that archive and writes to a new one from then on (`pg-r1`, then `pg-r2`, …): a recovered cluster cannot take over the old archive.

The order matters. **Never merge the switch to recovery while the old clusters run**: they would start writing to the new name, and the recovery would miss everything written after that.

1. **Confirm a completed base backup** newer than anything you must keep, for each cluster:

   ```bash
   kubectl --context kind-sorted-vintage get backups.postgresql.cnpg.io -A --sort-by=.metadata.creationTimestamp
   ```

   The newest in `sv-dev`, `sv-prod` and `keycloak` must be `completed`. If not, take one (a `Backup` with `method: plugin` for the cluster) and wait: they take up to 15 minutes. WAL written after the base backup is replayed too, as long as the archiver is current (`make backups-check`).
2. **Destroy:** `make destroy`.
3. **Merge the restore PR** in gitops: in each `restore.yaml`, replace `spec` with the recovery mode written in the file's comment (recover from the current name, archive to the next). Nothing reads it until the cluster exists again.
4. **Rebuild:** `make rebuild`. Each cluster recovers (about 4 minutes on an empty node, plus the first image pull), then the `Database` objects and roles come back with their fixed passwords.
5. **Check it:** run `sprints/sprint-3/verify_sprint3.sh` from the workstation. Previous orders and listings must be there, the verify users must sign in, and **Sprint 1's "continuous WAL archiving working" must pass**.
6. **Return to `initdb` mode** with a second gitops PR: each `restore.yaml` back to `initdb` mode with `serverName` set to the new name. It is harmless on the running clusters (proven in the spike) and makes the next restore start from the right archive.

## The timed drill through Jenkins (T077, SC-004)

Build `infra-terraform` with **REBUILD_DRILL** ticked (not with DESTROY). It runs the restore above with the clock running, one step per stage, using `scripts/lab/rebuild-drill.sh`:

1. **Two approvals**, as for DESTROY. Have nothing else in flight.
2. **Preflight** (read-only): every `restore.yaml` on gitops `main` is in `initdb` mode and names the archive its cluster writes to now, each cluster has a completed base backup, `make backups-check` passes, and the counts that must survive are saved (sv-dev orders and the newest order, listings in both environments, Keycloak users per realm).
3. **Destroy**: bootstrap, then cluster.
4. **Pause for the restore PR.** Merge it in gitops (step 3 above), then press *Merged, rebuild*. The stage checks that every file now recovers from the archive in use and writes to a new name; if not, it stops before applying.
5. **Apply**: cluster, then bootstrap, each planned just before it is applied, then wait up to 25 minutes for every Argo CD app.
6. **Data restored**: each cluster archives to its new name with `ContinuousArchiving` True, the newest order is back, and no count is lower than before.
7. **Purchase**: `sprints/sprint-3/verify_purchase.py` (a paid purchase, a declined card, a dead letter) as the verify users, from an app checkout beside the workspace, in a venv at `~/sv-spikes/rebuild-drill` (made from the seed service's pinned requirements the first time).

The build keeps `drill/rebuild-drill.json` and `drill/rebuild-drill.txt` as artifacts: the time of each step and **SC-004, from the start of the apply (an empty host) to the purchase passing, target under 30 minutes**. The destroy and the wait for your merge are reported apart. Then the usual verify stage runs. Afterwards, do step 6 above (back to `initdb` mode on the new names).

Each step can be run by hand as `bot` too, with `SV_GITOPS` (and `SV_APP` for the purchase) set; `preflight` and `check-data` only read.

## If something goes wrong

- **A cluster comes up empty and archiving fails** (`ContinuousArchiving False`, Sprint 1's archiving check fails): the restore PR was not merged, or a `restore.yaml` still names an archive already in use. The data is still in Garage. Destroy, fix the file (recover from the archive that holds the data, write to an unused name), rebuild.
- **"no target backup found"** in the recovery pod's log: there was no completed base backup under the name recovered from. Recover from an older archive name that has one, or rebuild without data.
- **A cluster stays in "Setting up primary"** for more than 10 minutes: the new archive name is already in use. Use the next unused name.
- **A service cannot reach its database** after a restore: compare the role's password with `secrets.auto.tfvars`; the fixed passwords must not have changed between the backup and the rebuild.

## Session stop and start

`make down` and `make up` keep everything (the node's volumes stay), with no restore involved. `make down` first checks, read-only, that every Postgres archive is current. The time from `make up` to healthy is SC-008 (T079), recorded in `sprints/sprint-4/sessions.md`.
