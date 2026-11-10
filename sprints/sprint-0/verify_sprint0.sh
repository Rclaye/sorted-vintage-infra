#!/usr/bin/env bash
# Sprint 0 verification. Run on the workstation from anywhere.
#   SV_ROOT  folder holding the three clones (default: ~/Sorted-Vintage/src)
#   SV_OWNER GitHub owner (default: the logged-in gh user)
#   MINI     ssh host for the lab host's admin account (default: SV_LAB_ADMIN_SSH from
#            scripts/lab/local.env, else lab-admin)
set -euo pipefail

SV_ROOT="${SV_ROOT:-$HOME/Sorted-Vintage/src}"
# Host and account names stay out of Git (ADR-0009): they come from the environment or from
# scripts/lab/local.env, which is git-ignored (copy scripts/lab/local.env.example).
INFRA="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -f "$INFRA/scripts/lab/local.env" ]]; then set -a; . "$INFRA/scripts/lab/local.env"; set +a; fi
MINI="${MINI:-${SV_LAB_ADMIN_SSH:-lab-admin}}"
REPOS=(sorted-vintage-infra sorted-vintage-app sorted-vintage-gitops)

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 && pass "tool: $1" || fail "tool missing: $1 (run: brew bundle --file scripts/Brewfile)"; }

echo "Workstation toolchain"
for t in git gh pre-commit gitleaks ssh; do need "$t"; done
gh auth status >/dev/null 2>&1 && pass "gh is logged in" || fail "gh is not logged in (gh auth login)"
SV_OWNER="${SV_OWNER:-$(gh api user --jq .login)}"

echo "Repositories (Ticket 0.2)"
for r in "${REPOS[@]}"; do
  d="$SV_ROOT/$r"
  [[ -d "$d/.git" ]] || fail "$r: no clone at $d"
  [[ -f "$d/.git/hooks/pre-commit" ]] && pass "$r: pre-commit hook installed" || fail "$r: run 'pre-commit install' in $d"
  if gitleaks git --help >/dev/null 2>&1; then gl=(gitleaks git "$d"); else gl=(gitleaks detect --source "$d"); fi
  "${gl[@]}" --no-banner --redact --exit-code 1 >/dev/null 2>&1 && pass "$r: full history has no secrets" || fail "$r: gitleaks found secrets"
  gh api "repos/$SV_OWNER/$r/rulesets" --jq '.[].name' 2>/dev/null | grep -qx protect-main \
    && pass "$r: main is protected" || fail "$r: no protect-main ruleset (run scripts/protect-main.sh)"
  [[ "$(gh api "repos/$SV_OWNER/$r" --jq .visibility)" == "public" ]] && pass "$r: public" || fail "$r: not public"
done

echo "Decision records and Spec Kit (Ticket 0.5)"
I="$SV_ROOT/sorted-vintage-infra"
for f in docs/adr/0001-local-kind-instead-of-eks.md docs/adr/0002-git-is-the-only-path-to-the-cluster.md \
         .specify/memory/constitution.md specs/001-marketplace-local-cloud/spec.md \
         specs/001-marketplace-local-cloud/plan.md specs/001-marketplace-local-cloud/tasks.md \
         docs/runbooks/remote-access.md; do
  [[ -f "$I/$f" ]] && pass "$f" || fail "missing $f"
done

echo "Lab host (Tickets 0.3 and 0.4)"
ssh -o BatchMode=yes -o ConnectTimeout=8 "$MINI" true 2>/dev/null && pass "ssh $MINI with a key" || fail "cannot ssh to $MINI with a key"
remote() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$MINI" "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; $1"; }
for t in kind terraform kubectl helm; do remote "command -v $t >/dev/null" && pass "lab host has $t" || fail "lab host is missing $t"; done
remote "docker info >/dev/null 2>&1" && pass "container runtime is running on the lab host" || fail "Docker Desktop is not running on the lab host"

echo
echo "Sprint 0 verification passed."
echo "Manual checks left: the SonarQube token is revoked, the old RDS password fails,"
echo "scripts/audit-old-secrets.sh reports no findings, and the router has no port forwarding rules."
