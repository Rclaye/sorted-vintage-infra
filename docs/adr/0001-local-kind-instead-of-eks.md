# ADR-0001: Run the platform on local Kind instead of Amazon EKS

- **Status:** Accepted
- **Date:** 2026-10-29

## Context

Earlier Clixx projects ran on AWS (EC2, ECS, kubeadm on EC2). Sorted Vintage needs a cluster that can run long working sessions over several months, keep its telemetry between sessions for the detection work, and be rebuilt cheaply. The program has a $0 recurring budget (constitution, Additional Constraints).

Available hardware: a Mac mini M4 with 16 GB, a MacBook Air M4 with 16 GB, and an Intel MacBook Pro with 8 GB.

## Decision

Run a multi-node Kind cluster (one control plane, two workers) on the Mac mini under Docker Desktop, created by Terraform. OrbStack is a lighter alternative if memory gets tight. Dev and prod are namespaces in that one cluster. All images are linux/arm64.

## Consequences

- No cloud cost, and no meter running between sessions. The lab runs while I work and is stopped otherwise.
- Everything above the cluster (Argo CD, GitOps layout, observability, policy) carries over to EKS unchanged. Only the `terraform/cluster` root is Kind-specific.
- AWS-specific skills (IAM roles for service accounts, load balancer controller, managed node groups) are not exercised here; the existing AWS projects already show them.
- One host is a single point of failure. Node failure can be simulated by stopping a Kind node container; a real multi-host cluster is a later option (k3s across the three Macs).
- Total memory for containers is capped at 12 GB, which shapes component choices (see the plan's memory budget).

## Alternatives considered

| Option | Why not |
| --- | --- |
| Amazon EKS | About $73 a month for the control plane alone, plus nodes, NAT and load balancers, with the added risk of forgetting to tear it down between sessions |
| Minikube | Single-node by default; Kind's multi-node clusters make node failure scenarios possible |
| k3s across the three Macs | Needs Linux VMs with bridged networking on each Mac; worth doing later, too fiddly for the foundation |
