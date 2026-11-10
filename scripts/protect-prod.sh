#!/usr/bin/env bash
# T080 (ADR-0002): the human gate for prod on the GitOps repo. Idempotent; run from the workstation as the
# repo owner, after the gitops prod-gate workflow is on main:
#   1. GitHub Environment "prod" with the owner as required reviewer. Self-review is allowed,
#      because this is a one-person project and the owner also starts promotions and reverts.
#   2. The protect-main ruleset requires pre-commit, secret-scan, policy and prod-gate.
#      Pull request approvals stay at zero.
#   3. Auto-merge is allowed, so bot pull requests (dev tags, promotions) merge once those
#      checks pass; prod-gate still waits for the environment approval on any prod change.
#      Merged branches are deleted automatically, so the next bot pull request can reuse a name.
# Usage: scripts/protect-prod.sh [github-owner]
set -euo pipefail
OWNER="${1:-$(gh api user --jq .login)}"
REPO="$OWNER/sorted-vintage-gitops"
OWNER_ID="$(gh api "users/$OWNER" --jq .id)"

gh api -X PUT "repos/$REPO/environments/prod" --input - >/dev/null <<JSON
{
  "prevent_self_review": false,
  "reviewers": [ { "type": "User", "id": $OWNER_ID } ],
  "deployment_branch_policy": null
}
JSON
echo "  environment prod: required reviewer $OWNER"

RULESET_ID="$(gh api "repos/$REPO/rulesets" --jq '.[] | select(.name=="protect-main") | .id')"
[ -n "$RULESET_ID" ] || { echo "protect-main ruleset not found; run scripts/protect-main.sh first"; exit 1; }
gh api "repos/$REPO/rulesets/$RULESET_ID" \
  | python3 -c '
import json, sys
r = json.load(sys.stdin)
want = ["pre-commit", "secret-scan", "policy", "prod-gate"]
for rule in r["rules"]:
    if rule["type"] == "required_status_checks":
        have = [c["context"] for c in rule["parameters"]["required_status_checks"]]
        rule["parameters"]["required_status_checks"] = [{"context": c} for c in dict.fromkeys(have + want)]
print(json.dumps({k: r[k] for k in ("name", "target", "enforcement", "conditions", "rules", "bypass_actors") if k in r}))
' | gh api -X PUT "repos/$REPO/rulesets/$RULESET_ID" --input - >/dev/null
echo "  protect-main: requires pre-commit, secret-scan, policy, prod-gate"

# delete_branch_on_merge: a bot branch left behind after auto-merge blocks the next push of the
# same name (a second promotion of the same tag failed this way on 2026-11-05).
gh api -X PATCH "repos/$REPO" -F allow_auto_merge=true -F delete_branch_on_merge=true >/dev/null
echo "  auto-merge allowed, merged branches deleted automatically"
