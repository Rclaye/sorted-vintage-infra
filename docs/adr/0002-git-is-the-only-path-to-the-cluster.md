# ADR-0002: Git is the only path to the cluster

- **Status:** Accepted
- **Date:** 2026-10-29

## Context

A common pipeline pattern gives CI credentials to the cluster and lets it run `kubectl apply` or `helm upgrade`. That spreads write access across tools, leaves no single audit trail, and makes drift invisible. From Project 5, an AI agent will also propose changes, and it must follow the same rules as people and pipelines (constitution, Principles I and III).

## Decision

- Argo CD is the only component that writes workloads to the cluster. It syncs from `sorted-vintage-gitops`.
- GitHub Actions builds, scans and publishes images, then commits the new image tag to the GitOps repo. It holds no cluster credentials.
- Jenkins runs infrastructure pipelines (plan, approval, apply). Its agent on the mini holds the kubeconfig to create, destroy and rebuild the cluster, install Argo CD and the bootstrap Secrets, and run read-only checks. It never writes a workload Argo CD manages. The exception is recorded in the plan's Complexity Tracking.
- Dev syncs automatically. Prod changes arrive as pull requests to `services/*/overlays/prod`.
- Rollback is `git revert`.

**Approval for prod.** GitHub does not let an author approve their own pull request, and this is a one-person project. Branch rules on `main` therefore require a pull request and passing checks, with zero approvals. The human approval gate for prod is a GitHub Environment named `prod` with a required reviewer, used by the promotion workflow. It is set up in Sprint 1.

## Consequences

- Every change to a running environment has a commit, an author and a review record.
- Argo CD can detect and reverse manual changes (drift).
- Emergency fixes are slower than `kubectl edit`; that is accepted.
- The remediation agent in Project 5 gets the same audit trail for free.

## Alternatives considered

| Option | Why not |
| --- | --- |
| CI deploys with `kubectl` or Helm | Spreads cluster credentials and loses drift detection |
| Argo CD Image Updater writes tags | Hides the tag change inside the cluster instead of a reviewed commit |
| Required PR approvals on main | Blocks a solo author from merging anything |
