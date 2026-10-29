# Sorted Vintage Platform Constitution

<!--
Sync Impact Report
- Version: 1.0.0 → 1.1.0 (MINOR: Principle III expanded, Principle VIII added)
- Modified: III. Gate Before Change (policy enforced in CI and at cluster admission)
- Added: VIII. Declarative, Reconciled Infrastructure
- Added constraint: no imperative webhooks that change cluster state
- Previous: 0.0.0 → 1.0.0 initial ratification (Principles I–VII)
- Templates requiring updates: plan-template.md (Constitution Check gates) ✅ aligned, tasks-template.md ✅ aligned
- Deferred items: none
-->

## Core Principles

### I. Git Is the Only Path to the Cluster
Every change to a running environment MUST arrive as a commit to the GitOps repository and be applied by Argo CD. No person, CI system or AI agent may run `kubectl apply`, `helm upgrade` or equivalent against dev or prod. CI systems MUST NOT hold cluster credentials. Emergency fixes follow the same path; a `git revert` is the rollback.

**Rationale:** one audit trail, one rollback mechanism, and drift that Argo CD can detect.

### II. Rebuildable From Code
The entire platform MUST be reproducible from an empty machine with one `terraform apply` followed by Argo CD sync. Manual setup steps are defects. A timed teardown and rebuild drill MUST be run and recorded at every project gate.

**Rationale:** recovery that is rehearsed is recovery that works; the drill time is a portfolio metric.

### III. Gate Before Change
Infrastructure changes MUST pass plan, review and explicit approval before apply. Promotion to prod MUST be an approved pull request. Policy-as-code is enforced twice: the same policies run in CI on every pull request and as admission control in the cluster, so a manifest that violates policy is rejected even if it is merged. From Project 5 onward, only change types listed in policy may auto-merge an agent-authored pull request; everything else waits for a human.

**Rationale:** the same control applies to people, pipelines and AI, and no single layer is trusted alone.

### IV. Measure Against Ground Truth (NON-NEGOTIABLE)
Every claim about detection, diagnosis or remediation MUST be scored against labeled Failure Lab incidents. Results are published with the method, the sample size and the failures, including results below target. Unscored AI output is a demo, not a deliverable.

**Rationale:** evaluation is what separates this program from a chatbot over logs.

### V. Observable by Default
Every service MUST expose `/healthz` and `/metrics`, emit structured JSON logs, and propagate OpenTelemetry trace context on every inbound and outbound call, including messages on the queue. A service without these is not done.

**Rationale:** the AIOps layer can only reason about what the platform emits.

### VI. Secure by Default
- No secrets in Git; gitleaks runs in pre-commit and CI.
- Images are scanned; a critical vulnerability fails the build.
- Payments run in Stripe test mode only; no real card data or real personal data enters the system.
- Workloads run as non-root with least-privilege service accounts.
- The lab is reachable only over the private Tailscale network; no router ports are opened.
- The AI investigator's tools are read-only.

### VII. Modest App, Deep Platform
The marketplace is the workload, not the product. Features beyond the version 1 definition of done are rejected until Gate 5 unless a Failure Lab scenario requires them. Prefer the simplest design that produces realistic failure modes.

### VIII. Declarative, Reconciled Infrastructure
Terraform creates only what must exist before Kubernetes: the cluster and the Argo CD bootstrap. Everything inside the cluster, including databases, buckets and their backups, MUST be declared as Kubernetes resources and reconciled by Argo CD and operators, not created by scripts. Remediation, rollback and promotion happen by changing declared state, never by webhooks or jobs that change the cluster imperatively.

**Rationale:** reconciled state repairs drift by itself and leaves the audit trail of Principle I.

## Additional Constraints

- **Cost:** $0 recurring. Free tiers and local tools only.
- **Hardware budget:** Mac mini M4 16 GB is the cluster host, with at most 12 GB allotted to containers. MacBook Air M4 16 GB runs local models. Intel MacBook Pro 8 GB runs Jenkins and SonarQube only.
- **Architecture:** all runtime images are linux/arm64.
- **Languages:** Python (FastAPI) and Java (Spring Boot) for services; Python for AIOps components; HCL for infrastructure.
- **CI split:** GitHub Actions builds and publishes application images; Jenkins runs infrastructure lifecycle pipelines.

## Development Workflow

- Work runs in two-week sprints. Each sprint has a spec (`sprintN.md`), a verify script (`verify_sprintN.sh`) that CI runs as its last stage, and a retro.
- Each project is a Spec Kit feature under `specs/NNN-name/` with `spec.md`, `plan.md` and `tasks.md`.
- Significant decisions are recorded as ADRs in `docs/adr/`; superseded ADRs are kept.
- Every merge to main goes through a pull request with passing checks.
- Each project gate ends with a published case study that leads with its measured result.

## Governance

This constitution supersedes conflicting practices in any spec, plan or task list. A plan's Constitution Check MUST pass, or any violation MUST be justified in its Complexity Tracking table. Amendments require an ADR, an updated Sync Impact Report and a version bump: MAJOR for removing or redefining a principle, MINOR for adding one, PATCH for wording.

**Version**: 1.1.0 | **Ratified**: 2026-10-29 | **Last Amended**: 2026-10-29
