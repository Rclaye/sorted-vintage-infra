# Sprint 0 Retrospective

## Outcome

Sprint 0 delivered a clean, protected starting point. The three Sorted Vintage repositories exist with secret scanning from their first commit, `main` accepts only pull requests with passing checks, and the Mac mini is reachable from the MacBook Air with the cluster toolchain installed and 73 GB of free disk. `verify_sprint0.sh` passed every automated check on 2026-10-28.

## Completed Work

### Ticket 0.1: Retire Clixx-Era Secrets

- The AWS account used for the Clixx projects no longer exists, so its RDS, EC2 and SonarQube hosts and their credentials are gone with it.
- The SonarQube token came from the class SonarQube account, whose server is believed to be gone, so the token no longer works.
- `scripts/audit-old-secrets.sh` scanned 12 public repositories. gitleaks found no secrets in any of them, but the file-history check found committed Terraform files in two:
    - `Clixx`: `terraform.tfstate`, its backup and `terraform.tfvars` (in two folders)
    - `Terraform_Clixx_Retail_Reporting_Infra`: three `terraform.tfvars` files
- Both repositories were made private rather than rewriting their history. None of the old Clixx passwords is reused anywhere.

### Ticket 0.2: Repositories With Guardrails

- Created `sorted-vintage-infra`, `sorted-vintage-app` and `sorted-vintage-gitops` as public repositories and pushed the scaffolds.
- First `checks` runs passed on all three: `pre-commit` and a full-history `secret-scan`, both on GitHub's arm64 runners.
- `scripts/protect-main.sh` applied the `protect-main` ruleset to all three: no deletion, no force push, pull request required, `pre-commit` and `secret-scan` must pass, zero required approvals.
- Local hooks installed in every clone. A test commit with a fake AWS key was blocked by gitleaks (rule `aws-access-token`).

### Ticket 0.3: Mac Mini as the Lab Host

- Installed Terraform (HashiCorp tap), kind, kubectl and Helm.
- Kept the existing Docker Desktop as the container runtime instead of installing OrbStack; memory set to 12 GB.
- Freed disk from 7.8 GB to 73 GB:

| Removed | Freed |
| --- | --- |
| Docker images and build cache from LocalMind's container era | 28.9 GB |
| Two leftover Docker volumes (one a duplicate of the native Ollama models) | 3.3 GB |
| Hugging Face cache (image-generation models no longer used) | 36 GB |

- Removing the remaining Ollama models from the mini was requested at the end of the sprint; LocalMind downloads them again when needed.

### Ticket 0.4: SSH From the Air to the Mini

- An SSH setup to the mini already existed. Created an ed25519 key on the Air, confirmed key login, and added `Host mac-mini` pointing at `ricomillzs-Mac-mini.local` rather than the DHCP address, so it survives address changes.

### Ticket 0.5: Decision Records and the Spec Kit Workspace

- ADR-0001 (local Kind instead of EKS) and ADR-0002 (Git is the only path to the cluster) committed.
- Spec Kit constitution v1.1.0 and the Project 1 spec, plan and tasks committed.

## Changes From the Spec

| Planned | Actual | Why |
| --- | --- | --- |
| Always-on mini (no sleep, auto-restart) | On only during working sessions, kept awake with Amphetamine | The lab is used in sessions; specs now require one-command start and stop with state surviving between sessions |
| `bootstrap-mac.sh` | Removed; tools installed directly with Homebrew | Keep setup minimal |
| OrbStack | Docker Desktop | Already installed; OrbStack stays an option if memory gets tight |
| Tailscale for remote access | Deferred; SSH over the home network | Not needed for sessions at home, and the Tailscale client misbehaved during setup |
| Self-hosted SonarQube on the Intel Mac | SonarQube Cloud free plan proposed for Sprint 1 | Free for public repositories, adds pull request analysis, needs no server |
| `brew bundle` on the Air | Not run | Everything the Air needs was already installed; its Terraform comes from homebrew-core, which would clash with the Brewfile's HashiCorp tap |

## What We Learned

- **gitleaks does not catch everything.** Database passwords in tfstate and tfvars are plain strings with no rule to match. The audit's file-history check is what caught the two old repositories.
- **zsh does not treat `#` as a comment when commands are typed in.** A pasted inline comment became arguments to `git commit`, which made the first leak test silently test nothing. Instructions should avoid inline comments.
- **`docker system prune -a --volumes` skips named volumes** in current Docker versions; they need `docker volume rm` or `docker volume prune -a`.
- **Disk, not RAM, was the real constraint on the mini.** Checking it before Sprint 1 avoided a failed cluster build.

## Follow-Ups

- [x] Make `Clixx` and `Terraform_Clixx_Retail_Reporting_Infra` private.
- [x] Check for reused Clixx passwords: none.
- [x] Class SonarQube server: believed gone, so its token is dead.
- [ ] Remove all Ollama models from the mini and confirm the space freed.
- [ ] Confirm the home router has no port forwarding rules.
- [ ] Add a passphrase to the Air's SSH key (`ssh-keygen -p -f ~/.ssh/id_ed25519`) and store it in the Keychain.
- [ ] Run `pre-commit autoupdate` in each repository as a pull request, as the first test of the branch rules.
- [ ] Quit Ollama before each Sorted Vintage session; never run LocalMind and the cluster together.
- [ ] Tailscale for working away from home: install on both Macs, name the mini `mac-mini`, disable its key expiry, add a `mac-mini-ts` SSH alias, test from a phone hotspot.
