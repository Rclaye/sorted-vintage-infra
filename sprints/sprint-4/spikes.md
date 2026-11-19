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
