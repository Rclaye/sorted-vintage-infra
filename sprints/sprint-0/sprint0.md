Sorted Vintage — Sprint 0 Actionable Engineering Specification
Document Status: Approved for execution
Target Release: Sprint 0, Preparation (Oct 24 – Nov 1, 2026)
Author: Platform Engineering

1. Executive Summary & Sprint 0 Objective

Sprint 0 creates a clean, safe and reachable starting point before any platform code is written. It retires secrets left over from the Clixx AWS work, creates the three Sorted Vintage repositories with secret scanning from the first commit, sets up the Mac mini as the lab host for working sessions, and records the first two architecture decisions.

Sprint Objective
Every repository exists with guardrails on, no old credential is still live or public, and `ssh mac-mini` works from the MacBook Air.

2. Lab Topology After Sprint 0

                  ┌─────────────────────────────── Tailscale (private network, no open ports) ───────────────────────────────┐
                  │                                                                                                          │
   ┌──────────────▼──────────────┐          ┌──────────────────────────────┐          ┌──────────────────────────────┐      │
   │  MacBook Air M4 (16 GB)     │   ssh    │  Mac mini M4 (16 GB)         │          │  MacBook Pro Intel (8 GB)    │      │
   │  Workstation                ├─────────►│  Lab host (on when working)  │          │  CI (from Sprint 1)          │◄─────┘
   │  Editor, git, pre-commit    │          │  Docker, kind, terraform     │          │  Jenkins, SonarQube          │
   └──────────────┬──────────────┘          └──────────────────────────────┘          └──────────────────────────────┘
                  │ git push
   ┌──────────────▼──────────────────────────────────────────────────────────────────────────────────┐
   │  GitHub: sorted-vintage-infra · sorted-vintage-app · sorted-vintage-gitops (pre-commit CI, rules) │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘

3. Actionable Engineering Tickets & Implementation Specs

Ticket 0.1 — Retire Clixx-Era Secrets
Owner: Security / Platform Engineer
Story: As the platform owner, I want every credential from the old Clixx AWS work revoked or rotated, and confirmed absent from public repositories, so that publishing a new portfolio project cannot expose an old one.

Findings that triggered this ticket (from the local folders):
- `CliXX_Retail_Repository/sonar-project.properties` contains a SonarQube token and a public server address (3.84.148.19:9000).
- `CliXX_Retail_Repository/wp-config.php` contains an RDS hostname and database password.
- Every `terraform.tfvars` in `Full-deployment` and `Terraform_Local` contains database and WordPress admin passwords.
- `terraform.tfstate` files exist in `MONOLITHIC_APP`, `MONO_APP_REFINED/environments/dev` and `Full-deployment`; state stores secrets in plain text.
- `wordpressdb_dump.sql` contains a WordPress admin password hash.

Implementation Requirements:
- Revoke the SonarQube token in the SonarQube UI (My Account → Security), or terminate the server if it is no longer used.
- In AWS: confirm whether the RDS instances, EC2 instances and the SonarQube host still exist; destroy them or rotate their passwords. Check for leftover NAT gateways and Elastic IPs that still bill.
- Run `scripts/audit-old-secrets.sh`, which clones every public repository on the GitHub account, runs gitleaks over full history and lists any tfstate, tfvars, wp-config or sonar properties files ever committed.
- For any hit: rotate the credential first, then remove the file from history or make the repository private.
- Keep the SQL dump and the old folders out of every Sorted Vintage repository.

Acceptance Criteria Verification:
- The SonarQube token is revoked and the old RDS password no longer authenticates (or the instance is gone).
- `audit-old-secrets.sh` reports zero findings, or every finding is listed in the retro with its rotation date.

Ticket 0.2 — Repositories With Guardrails From the First Commit
Owner: Platform Engineer
Story: As the platform owner, I want three repositories that refuse secrets and unreviewed changes from day one, so that the project's public history is clean from its first commit.

Implementation Requirements:
- Create public repositories `sorted-vintage-infra`, `sorted-vintage-app` and `sorted-vintage-gitops` with the scaffolds in this sprint.
- Each repository carries `.gitignore`, `.pre-commit-config.yaml` (gitleaks, private-key detection, large-file check, YAML checks), `LICENSE`, `CODEOWNERS`, a pull request template and a `checks` workflow that runs pre-commit on every pull request.
- Install hooks locally: `pre-commit install` in each clone, then `pre-commit autoupdate` to pin current hook versions.
- Apply a branch ruleset to `main` with `scripts/protect-main.sh`: pull request required, the `checks` workflow must pass, force pushes and deletion blocked. Required approvals stay at 0, because GitHub does not let an author approve their own pull request.
- The human approval gate for prod moves to a GitHub Environment named `prod` with a required reviewer, set up in Sprint 1. It is recorded in ADR-0002.

Acceptance Criteria Verification:
- A commit containing a test AWS key is blocked locally by pre-commit and, if forced, fails the `checks` workflow.
- A direct push to `main` is rejected.
- All three repositories show a green `checks` run on their first pull request.

Ticket 0.3 — Mac Mini as the Lab Host
Owner: Platform / SRE Engineer
Story: As the platform owner, I want the Mac mini to carry the platform toolchain and stay awake while I work, so that Sprint 1 can build the cluster on it.

The lab runs in working sessions, not around the clock: the mini is on while I work and off otherwise.

Implementation Requirements:
- Install the toolchain: `brew bundle --file scripts/Brewfile` (kind, kubectl, Helm, Terraform, gh, pre-commit, gitleaks) plus Docker Desktop as the container runtime. Review the Brewfile first.
- Keep the mini awake during a session with Amphetamine.
- System Settings → General → Sharing: turn on Remote Login, so the Air can connect over SSH.
- Docker Desktop → Settings → Resources: 12 GB of memory.

Acceptance Criteria Verification:
- `kind version`, `terraform version` and `docker info` succeed on the mini.

Ticket 0.4 — SSH From the Air to the Mini
Owner: Platform Engineer
Story: As the platform owner, I want to work on the mini from the MacBook Air, so that I can edit, run Terraform and open dashboards from one machine.

Implementation Requirements:
- On the Air: `brew bundle --file scripts/Brewfile`, create an SSH key if there is none (`ssh-keygen -t ed25519`), and copy it to the mini (`ssh-copy-id <user>@<mini-address>`).
- Add a `Host mac-mini` entry to `~/.ssh/config` on the Air.
- Optional, for working away from home: install Tailscale on both machines. No router ports are opened either way.
- Write `docs/runbooks/remote-access.md`: how to connect and how to tunnel Argo CD and Grafana.

Acceptance Criteria Verification:
- `ssh mac-mini hostname` succeeds from the Air with key login.

Ticket 0.5 — Decision Records and the Spec Kit Workspace
Owner: Platform Engineer
Story: As a reviewer of this portfolio, I want the first decisions written down with their reasons, so that later case studies can point back to them.

Implementation Requirements:
- Commit ADR-0001 (local Kind instead of EKS) and ADR-0002 (Git is the only path to the cluster) to `docs/adr/`.
- Commit the Spec Kit workspace (`.specify/memory/constitution.md` and `specs/001-marketplace-local-cloud/`) to `sorted-vintage-infra`.

Acceptance Criteria Verification:
- Both ADRs are merged through pull requests with green checks.
- `specs/001-marketplace-local-cloud/` contains spec.md, plan.md and tasks.md.

4. Sprint Verification

Run `sprints/sprint-0/verify_sprint0.sh` from the MacBook Air. It checks the local toolchain, the pre-commit hooks in each clone, a full-history gitleaks scan, branch rules on GitHub and the mini over SSH. It exits non-zero on the first failure.

5. Out of Scope for Sprint 0

Kind cluster creation, Argo CD, Jenkins and any service code. These start in Sprint 1.
