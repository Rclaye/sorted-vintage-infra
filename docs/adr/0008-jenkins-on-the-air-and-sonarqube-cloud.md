# ADR-0008: Jenkins on the Air, SonarQube Cloud, and a one-command rebuild

- **Status:** Accepted
- **Date:** 2026-10-30
- **Amends:** constitution 1.1.0 → 1.2.0 (MINOR)

## Context

Constitution 1.1.0 put Jenkins and a self-hosted SonarQube on the Intel MacBook Pro, and Principle II asked for the platform to come back from "one `terraform apply`". Sprint 0 and research R15 changed both:

- Keeping the Intel Mac closed to the home network needed a reverse SSH tunnel and firewall rules, and it had to be on for every session. It was tried and dropped on 2026-10-30.
- Self-hosted SonarQube needs about 2 GB and a server to patch. SonarQube Cloud is free for public repositories and decorates pull requests.
- The plan keeps two Terraform roots, `cluster` (replaceable) and `bootstrap` (Argo CD and its secrets), so the cluster can be swapped without touching the bootstrap. That is two applies, wrapped in `make rebuild`, which `/speckit-analyze` flagged as a conflict with the literal wording of Principle II.

## Decision

- **Two machines.** The Mac mini is the cluster host and the Jenkins build agent (label `lab`). The MacBook Air runs local models and the Jenkins controller, as its own standard account `ricomillz` through a LaunchDaemon, bound to `127.0.0.1:8080`, with zero executors and one job (`infra-terraform`, `main` only). The Intel MacBook Pro leaves the lab.
- **Code analysis** uses SonarQube Cloud's free plan, run from the app repository's GitHub Actions, with the quality gate on each pull request.
- **Principle II** reads "one command, `make rebuild`, which applies the Terraform roots in order and waits for Argo CD to sync". The two roots stay. The intent is unchanged: an empty machine comes back with no manual step.

### Constitution amendment

| Section | 1.1.0 | 1.2.0 |
| --- | --- | --- |
| II. Rebuildable From Code | one `terraform apply` followed by Argo CD sync | one command, `make rebuild`, which applies the Terraform roots in order and waits for Argo CD to sync |
| Hardware budget | three machines; Intel MacBook Pro runs Jenkins and SonarQube | two machines; the mini is also the Jenkins agent; the Air also runs the Jenkins controller as its own standard account |
| CI split | GitHub Actions builds images; Jenkins runs infrastructure pipelines | adds code analysis on SonarQube Cloud from GitHub Actions |

**Why MINOR.** Governance reserves PATCH for wording and MAJOR for removing or redefining a principle. A machine leaving the lab and a changed rebuild mechanism are more than wording, but no principle is removed and Principle II keeps its meaning.

## Consequences

- One machine fewer to power on, patch and secure each session.
- The Air holds the agent key and the Jenkins credentials store. Neither gives cluster access; the kubeconfig stays on the mini. Running Jenkins as a separate standard account keeps it away from the everyday account's keys and files, provided that home folder is `chmod 700` (runbook).
- Jenkins is available only while the Air is awake, which is exactly when a session runs. Jobs poll Git, because GitHub cannot reach the controller.
- Memory on the Air is tighter when a local model runs alongside Jenkins; stop Jenkins first if needed.
- Analysis results live in SonarQube Cloud, outside the lab.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Keep Jenkins on the Intel Mac | A third machine on every session, and a reverse tunnel plus firewall rules to keep it off the home network |
| Jenkins on the mini | Competes with the cluster for the 4 GB left outside Docker |
| A GitHub Actions self-hosted runner instead of Jenkins | Simpler, but drops the Jenkins-versus-Actions comparison the program plans to publish |
| Merge the Terraform roots so one `terraform apply` is literally true | Loses the replaceable `cluster` root and the order between creating the cluster and installing Argo CD |
