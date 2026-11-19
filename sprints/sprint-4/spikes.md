# Sprint 4 Spikes

Each spike runs on a throwaway Kind cluster `sv-spike` (or a throwaway container) on the lab host, with the lab's versions, before the ticket that depends on it changes the lab. `sv-spike` is deleted afterwards.

## Postgres recovery from the Barman Cloud Plugin archive (Ticket 4.1, T076, T110)

**Pass with a design change**, 2026-11-19. Kind node `kindest/node:v1.37.0` (the lab's), cert-manager v1.21.3, CloudNativePG chart 0.29.1, plugin-barman-cloud 0.8.1, Garage v2.5.0 in the same namespace as the cluster, `ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie`; the lab's `ObjectStore` (gzip, `s3://backups/postgres`) and a `Cluster` like `platform/postgres/base` (one instance, a managed role, `archive_timeout`, the plugin as WAL archiver).

| Step | Result |
| --- | --- |
| Source cluster `pg`, `initdb` | Ready in 367 s (mostly the first pull of the Postgres image onto a fresh node) |
| Base backup, `method: plugin` | completed |
| 100 rows before the backup, 25 after, then `pg_switch_wal()` | 125 rows, WAL archived |
| Delete the cluster and its volume (as `destroy` would) | gone |
| **Recover as `pg`, archiving under the same server name** (the plugin's default, the cluster's name) | **never Ready**: "Setting up primary" for over 7 minutes, then abandoned |
| **Recover as `pg`, archiving under a new server name `pg-r1`** (`externalClusters` source: the plugin with `serverName: pg`) | **Ready in 206 s with all 125 rows**, the 25 written after the base backup replayed from WAL; continuous archiving working under `pg-r1` |

Phases seen during the good recovery, which is what Argo CD's health shows meanwhile: "Setting up primary" (about 2.5 minutes), "Waiting for the instances to become active", "Cluster in healthy state".

What it means for T076 and T110:

- **Every restore archives under a new server name.** A recovered cluster cannot take over the archive folder of the cluster it recovers from. So the committed restore mode is per environment and names two things: the server name to recover **from** (the archive in use) and the one to archive **to** from then on (`pg`, then `pg-r1`, then `pg-r2` after the next restore). The next restore recovers from the newest name.
- The cluster keeps its name (`pg`): Services, Secrets and the services' `DATABASE_URL` do not change.
- Same pattern, a separate entry, for the Keycloak database cluster (`keycloak-db`).
- Not seen yet: the managed roles (`orders`, `payments`, `notifications`) after the good recovery (checked only on the failed one), and the `Database` objects adopting the restored databases. Check both when T076 is tried on `sv-spike` with the lab's real manifests, before the lab.
- A first pull of the Postgres image takes minutes on an empty node: the rebuild drill's 30-minute budget (SC-004) must allow for image pulls.

## Postgres restore mode with the lab's own manifests (Ticket 4.1, T076, T110)

**Pass, with one guard needed**, 2026-11-19. On `sv-spike` with the same versions as above: `platform/postgres/base` rendered by kustomize into namespace `sv-dev` (the `Cluster`, its three `Database` objects, the `ScheduledBackup` and the `ObjectStore`), the `pg-*-app` and `s3-backups` Secrets made as Terraform makes them, and a patch per mode.

| Step | Result |
| --- | --- |
| 1. `initdb` mode, as the lab has it | Ready; `Database` objects for orders, payments, notifications applied; the ScheduledBackup's immediate base backup **completed after 576 s** |
| 2. Destroy (manifests, Backups, volume), then **recovery mode** (recover from `pg`, archive to `pg-r1`) | **Ready in 239 s**, all data back (listings 40 rows, orders 7); the three `Database` objects applied again; the roles orders, payments, notifications and listings each **signed in with its Secret's password**; continuous archiving working under `pg-r1` |
| 3. **Back to `initdb` mode** (archive to `pg-r1`) applied to the live recovered cluster | **Accepted, no restart**, data untouched, archiving still working: a bootstrap change on a running cluster is ignored |
| 4. Destroy, then `initdb` mode archiving into the non-empty `pg-r1` (a rebuild that **forgot to bump** the names) | **Came up Ready and empty**; only archiving failed: `ContinuousArchiving False` ("unexpected failure invoking barman-cloud-wal-archive") |

An earlier run of the same spike recovered nothing ("no target backup found"): it destroyed the cluster about 3 minutes after the immediate backup started, before the backup completed. The lab's daily backups do complete (checked read-only in sv-dev, sv-prod and keycloak on 2026-11-19, latest 03:18 UTC), but some took 15 minutes.

What it means for T076, T110, T077 and T078:

- **The restore mode is a committed file per environment** (and one for `keycloak-db`), normally in `initdb` mode naming the archive in use. A restore is one pull request that switches it to recovery from the archive in use to the next name; after the restore, a second one returns it to `initdb` mode on the new name (step 3: harmless on the live cluster).
- **Order of a restore: confirm a completed base backup, destroy, merge the restore PR, apply.** Never merge the switch while the old cluster runs: it would start archiving to the new name and the recovery would miss everything written after that.
- **The drill waits for a completed base backup** newer than the last change it must keep (or takes one and waits, up to 15 minutes) before it destroys anything.
- **A forgotten bump is silent except for archiving** (step 4). Sprint 1's verify check "continuous WAL archiving working", run on every Jenkins build, fails in exactly that state; the runbook says to treat that failure after a rebuild as "restore not done".
- Recovery itself took 3.5 to 4 minutes per cluster on an empty node; with the image pull and the platform, SC-004's 30 minutes looks reachable but has little slack.
