#!/usr/bin/env bash
# Sprint 0, Ticket 0.2: apply a ruleset to main on each Sorted Vintage repo.
# Run AFTER the first commit has been pushed to main.
# Usage: scripts/protect-main.sh [github-owner]
set -euo pipefail
OWNER="${1:-$(gh api user --jq .login)}"

for repo in sorted-vintage-infra sorted-vintage-app sorted-vintage-gitops; do
  if gh api "repos/$OWNER/$repo/rulesets" --jq '.[].name' | grep -qx "protect-main"; then
    echo "  $repo: ruleset already present"; continue
  fi
  gh api -X POST "repos/$OWNER/$repo/rulesets" --input - >/dev/null <<JSON
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "pre-commit" }, { "context": "secret-scan" } ] } }
  ]
}
JSON
  echo "  $repo: ruleset applied"
done
