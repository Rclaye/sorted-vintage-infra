#!/usr/bin/env bash
# Sprint 0, Ticket 0.1: scan every public repo on a GitHub account for leaked secrets
# and for files that should never have been committed.
# Usage: scripts/audit-old-secrets.sh [github-owner]
set -euo pipefail

command -v gh >/dev/null || { echo "gh is required"; exit 1; }
command -v gitleaks >/dev/null || { echo "gitleaks is required"; exit 1; }

OWNER="${1:-$(gh api user --jq .login)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
RISKY='(\.tfstate(\.backup)?$|(^|/)terraform\.tfvars$|\.tfvars\.json$|wp-config\.php$|sonar-project\.properties$|\.pem$|id_rsa|\.sql$|\.env$)'
findings=0

scan() {  # gitleaks renamed "detect" to "git" in v8.19; support both
  if gitleaks git --help >/dev/null 2>&1; then
    gitleaks git "$1" --no-banner --redact --exit-code 1 >/dev/null 2>&1
  else
    gitleaks detect --source "$1" --no-banner --redact --exit-code 1 >/dev/null 2>&1
  fi
}

echo "Auditing public repositories of $OWNER"
while read -r repo; do
  [[ -z "$repo" ]] && continue
  dir="$WORK/$repo"
  git clone --quiet --no-checkout "https://github.com/$OWNER/$repo.git" "$dir" 2>/dev/null || { echo "  ! $repo: clone failed"; continue; }

  leak="clean"; scan "$dir" || { leak="SECRETS FOUND"; findings=$((findings+1)); }
  files="$(git -C "$dir" log --all --name-only --format= | sort -u | grep -Ei "$RISKY" || true)"
  [[ -n "$files" ]] && findings=$((findings+1))

  printf '  %-40s gitleaks: %s\n' "$repo" "$leak"
  [[ -n "$files" ]] && printf '      ever-committed risky files:\n%s\n' "$(sed 's/^/        /' <<<"$files")"
done < <(gh repo list "$OWNER" --visibility public --limit 200 --json name --jq '.[].name')

echo
if ((findings)); then
  echo "$findings finding(s). Rotate each credential FIRST, then remove the file from history or make the repo private."
  echo "Details for one repo: gitleaks git <clone-dir> --verbose --redact"
  exit 1
fi
echo "No findings."
