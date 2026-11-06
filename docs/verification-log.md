# Verification log

Every acceptance check from the sprint tickets, with how it was checked, the result and where the evidence is. Automated checks also run in `sprints/sprint-N/verify_sprintN.sh`, which Jenkins runs at the end of every `infra-terraform` build; this log is mainly for the checks a script cannot do on its own: timings, approvals, drills, and anything done by hand.

**How to add an entry:** when a ticket closes, add one row per acceptance check. Say what was run, what came back, the date, and a link (PR, build number, `spikes.md` section or retro). If a check was skipped or only partly done, mark it **Open** and list it under [Open checks](#open-checks) instead of leaving it out.

Status: **Pass**, **Open** (not done or not recorded), **Partial** (done, but not the way the ticket asks).

## Open checks

| Ticket | Check | What is missing |
| --- | --- | --- |
| 0.2 | A commit with a test key, if forced past the hook, fails the `checks` workflow | Only the local hook was tested (Sprint 0 retro). Push a branch with a fake key using `git commit --no-verify` and confirm `secret-scan` fails on its PR; then close the PR and delete the branch. |
| 0.2 | A direct push to `main` is rejected | The ruleset was applied, but the push test is not recorded. `git push origin HEAD:main` from a clean clone should be refused. |
| 1.4 | A pull request that adds a bad manifest under a service overlay fails its policy check | Run locally with `scripts/policy-check.sh` only (`spikes.md`, T026: "CI run pending"). Open a throwaway gitops PR with a bad overlay and confirm the `policy` job fails. |

## Sprint 0

| Ticket | Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- | --- |
| 0.1 | The old SonarQube token is revoked and the old RDS password no longer works | The AWS account that held RDS, EC2 and the SonarQube host no longer exists; the class SonarQube server is believed gone | Pass, by removal | 2026-10-28 | Sprint 0 retro |
| 0.1 | `audit-old-secrets.sh` reports zero findings, or each is listed with its fix | gitleaks over 12 public repos found nothing; the file-history check found Terraform state and tfvars in two repos, which were made private | Pass | 2026-10-28 | Sprint 0 retro |
| 0.2 | A commit with a test AWS key is blocked locally | Test commit with a fake key | Pass: gitleaks rule `aws-access-token` blocked it | 2026-10-28 | Sprint 0 retro |
| 0.2 | ...and, if forced, fails the `checks` workflow | | **Open** | | [Open checks](#open-checks) |
| 0.2 | A direct push to `main` is rejected | | **Open** | | [Open checks](#open-checks) |
| 0.2 | All three repos show a green `checks` run on their first PR | First PR in each repo | Pass: `pre-commit` and `secret-scan` green | 2026-10-28 | Sprint 0 retro |
| 0.3 | `kind version`, `terraform version`, `docker info` succeed on the mini | Ran on the mini | Pass; disk freed from 7.8 GB to 73 GB first | 2026-10-28 | Sprint 0 retro |
| 0.4 | `ssh mac-mini hostname` succeeds with key login | From the Air | Pass | 2026-10-28 | Sprint 0 retro |
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
| `terraform apply` for `cluster` then `bootstrap` succeeds, and a second plan shows no changes | Applied on the mini as `bot`; plans re-run by the verify script | Pass | 2026-11-02, rechecked 2026-11-05 | infra #7; `verify_sprint1.sh` |
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
| A PR adding a bad manifest under a service overlay fails its policy check | `scripts/policy-check.sh` locally | **Partial**: local only | 2026-11-03 | [Open checks](#open-checks) |

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
| Jenkins listens on `127.0.0.1:8080` only, as the Air's `ricomillz`, and answers | `netstat` and `ps` (no sudo) from the Air | Pass | 2026-11-05 | `verify_sprint1.sh` (Air mode) |
| The everyday account cannot read the agent key; the Air's `ricomillz` is not an admin | File read test; `dsmemberutil` | Pass | 2026-11-05 | `verify_sprint1.sh` (Air mode) |
| Exactly one job, `infra-terraform`, building `main` only | Defined in `jenkins/casc.yaml`; UI shows the one job | Pass | 2026-11-05 | `casc.yaml`; Jenkins UI |
| The `mac-mini` agent runs as `bot` (not an admin) and a run shows plan, a paused approval and apply | A `terraform_data` record gave the pipeline a harmless change | Pass: `1 to add`, paused, approved by Richard, applied, `verify` green | 2026-11-05 | infra #25; build #6 |
| A PR to `sorted-vintage-app` shows the SonarQube Cloud quality gate | PR check and bot comment; SonarQube Cloud API | Pass: "Quality Gate passed" | 2026-11-05 | app #4; `verify_sprint1.sh` |
| Every Jenkins build checks the live lab (T107) | `verify` stage running the sprint's script with `MINI=local` | Pass | 2026-11-05 | infra #23; builds #4–#6 |

### Ticket 1.8: verify and measure

| Check | How | Result | Date | Evidence |
| --- | --- | --- | --- | --- |
| `verify_sprint1.sh` passes | From the Air, and on the mini as the Jenkins `verify` stage | Pass | 2026-11-05 | infra #23; builds #4–#6 |
| The retro records measured memory by component next to the plan | Prometheus working sets now and over 24 h | Pass: 6.16 GiB of pods against the plan's 9.5 GB | 2026-11-05 | Sprint 1 retro |
