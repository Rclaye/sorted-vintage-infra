# sorted-vintage-infra

Infrastructure, pipelines and documentation for **Sorted Vintage**, a peer-to-peer resale marketplace running on a local Kubernetes platform that detects, diagnoses and safely fixes its own incidents.

| Repo | Role |
| --- | --- |
| **sorted-vintage-infra** (this one) | Terraform, Jenkins pipelines, ADRs, runbooks, Spec Kit specs, sprint plans |
| [sorted-vintage-app](https://github.com/Rclaye/sorted-vintage-app) | Service code and GitHub Actions image pipelines |
| [sorted-vintage-gitops](https://github.com/Rclaye/sorted-vintage-gitops) | Desired state that Argo CD applies to the cluster |

## Layout

```text
.specify/            Spec Kit memory (the project constitution)
specs/               Spec Kit features: spec, plan and tasks per project
sprints/sprint-N/    Sprint spec, verify script and retro
docs/adr/            Architecture decision records
docs/runbooks/       Operating procedures
scripts/             Lab setup and audit scripts
terraform/           Cluster and bootstrap roots (from Sprint 1)
```

## Start here

1. [Constitution](.specify/memory/constitution.md): the rules every change follows.
2. [Project 1 spec](specs/001-marketplace-local-cloud/spec.md), [plan](specs/001-marketplace-local-cloud/plan.md) and [tasks](specs/001-marketplace-local-cloud/tasks.md).
3. [Sprint 0](sprints/sprint-0/sprint0.md): preparation.
4. [ADR-0001](docs/adr/0001-local-kind-instead-of-eks.md) and [ADR-0002](docs/adr/0002-git-is-the-only-path-to-the-cluster.md).

## Set up a machine

```bash
brew bundle --file scripts/Brewfile
```

The [Brewfile](scripts/Brewfile) lists the toolchain. The remaining setup steps are in [Sprint 0](sprints/sprint-0/sprint0.md), Tickets 0.3 and 0.4.
