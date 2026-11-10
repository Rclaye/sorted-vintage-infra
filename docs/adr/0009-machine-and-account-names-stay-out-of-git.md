# ADR-0009: Machine and account names stay out of Git

- **Status:** Accepted
- **Date:** 2026-11-09
- **Amends:** constitution 1.2.0 → 1.2.1 (PATCH, wording)

## Context

These repositories are public. Until now the documents, scripts and the Jenkins configuration named the lab's machines by model, an operating-system account by name, and the lab host by its local hostname. None of that gives access to the lab: no router port is open, ingress is bound to loopback, and SSH accepts keys only. It is still personal detail that a reader does not need, and it helps anyone trying to guess their way around the network.

## Decision

- Documents use roles, not names: the **lab host** (cluster and Jenkins agent), the **workstation** (editor and Jenkins controller), the **lab account** `bot`, the **admin account** and the **Jenkins account**.
- Scripts read the names that belong to real machines from the environment or from `scripts/lab/local.env`, which is git-ignored. `scripts/lab/local.env.example` lists them: `SV_JENKINS_USER`, `SV_LAB_HOST`, `SV_LAB_SSH` and `SV_LAB_ADMIN_SSH`.
- `jenkins/casc.yaml` takes the lab host's name from `SV_LAB_HOST`, which `scripts/jenkins/air-setup.sh` writes into the Jenkins LaunchDaemon.
- Hardware is described by what constrains the design (16 GB, arm64), not by model.
- Local editor and assistant tooling folders are git-ignored.

## Consequences

- A script run from the workstation stops with a clear message if `local.env` is missing. The lab host needs no copy, because Jenkins runs the verify scripts there with `MINI=local`.
- The running Jenkins controller keeps its current configuration until `air-setup.sh` is run again; that run renames the agent node to `lab-host` (its label, `lab`, is unchanged, so the pipeline is not affected).
- Runbook commands use the SSH aliases `lab` and `lab-admin`; each operator defines them in `~/.ssh/config`.
- Earlier commits still contain the old names. Rewriting history was not done.
- The names `MINI`, `MINI_INFRA` and `mini-agent-ssh` stay as internal identifiers.
