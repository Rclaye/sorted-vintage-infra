#!/usr/bin/env bash
# Sprint 1 verification. Run on the MacBook Air with the lab up (make up on the mini).
# Read-only: it changes nothing in the cluster (server-side dry runs only).
#   SV_ROOT     folder holding the three clones on the Air (default: ~/Sorted-Vintage/src)
#   SV_OWNER    GitHub owner (default: the logged-in gh user)
#   MINI        ssh host for the Mac mini (default: mac-mini)
#   MINI_INFRA  sorted-vintage-infra clone on the mini (default: $HOME/Sorted-Vintage/src/sorted-vintage-infra on the mini)
set -euo pipefail

SV_ROOT="${SV_ROOT:-$HOME/Sorted-Vintage/src}"
MINI="${MINI:-mac-mini}"
MINI_INFRA="${MINI_INFRA:-\$HOME/Sorted-Vintage/src/sorted-vintage-infra}"  # expanded on the mini
CLUSTER=sorted-vintage
NODE="$CLUSTER-control-plane"
G="$SV_ROOT/sorted-vintage-gitops"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; }
remote() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$MINI" "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; $1"; }
k() { remote "kubectl --context kind-$CLUSTER $1"; }

echo "Workstation"
for t in gh ssh curl lsof; do command -v "$t" >/dev/null 2>&1 && pass "tool: $t" || fail "tool missing: $t"; done
SV_OWNER="${SV_OWNER:-$(gh api user --jq .login)}"
[[ -d "$G/.git" ]] || fail "no gitops clone at $G"

echo "Mac mini toolchain (Ticket 1.1)"
ssh -o BatchMode=yes -o ConnectTimeout=8 "$MINI" true 2>/dev/null && pass "ssh $MINI" || fail "cannot ssh to $MINI"
for t in kind terraform kubectl helm mkcert stripe kyverno tfsec; do
  remote "command -v $t >/dev/null" && pass "mini has $t" || fail "mini is missing $t (brew bundle --file scripts/Brewfile)"
done
remote "test -f $MINI_INFRA/sprints/sprint-1/spikes.md" && pass "spikes.md recorded" || fail "missing sprints/sprint-1/spikes.md on the mini clone"

echo "Cluster (Ticket 1.2)"
remote "kind get clusters" | grep -qx "$CLUSTER" && pass "kind cluster $CLUSTER exists" || fail "no kind cluster $CLUSTER"
nodes="$(k "get nodes --no-headers" | wc -l | tr -d ' ')"
[[ "$nodes" == 1 ]] && pass "single node (research R1)" || fail "expected 1 node, found $nodes"
for p in 80 443; do
  b="$(remote "docker port $NODE $p")"
  [[ "$b" == "127.0.0.1:$p" ]] && pass "port $p bound to loopback only" || fail "port $p bound to '$b', expected 127.0.0.1:$p (research R2)"
done
for root in cluster bootstrap; do
  set +e; remote "terraform -chdir=$MINI_INFRA/terraform/$root plan -detailed-exitcode -input=false -lock=false >/dev/null 2>&1"; rc=$?; set -e
  [[ $rc == 0 ]] && pass "terraform/$root: no changes" || fail "terraform/$root: plan exit $rc (2 = changes pending)"
done
tracked="$(git -C "$SV_ROOT/sorted-vintage-infra" ls-files '*.tfvars' '*.tfvars.json')"
[[ -z "$tracked" ]] && pass "no tfvars tracked" || fail "tfvars tracked in Git: $tracked"

echo "Argo CD (Ticket 1.3)"
apps="$(k "get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{\"\n\"}{end}'")"
[[ -n "$apps" ]] || fail "no Argo CD Applications found"
bad="$(awk '$2!="Synced" || $3!="Healthy"' <<<"$apps")"
[[ -z "$bad" ]] && pass "$(wc -l <<<"$apps" | tr -d ' ') applications Synced and Healthy" || fail "not synced or healthy: $(tr '\n' ';' <<<"$bad")"

echo "Backups (Ticket 1.3, research R14)"
for ns in sv-dev sv-prod; do
  st="$(k "get clusters.postgresql.cnpg.io -n $ns -o jsonpath='{.items[*].status.conditions[?(@.type==\"ContinuousArchiving\")].status}'")"
  [[ -n "$st" && "$st" != *False* ]] && pass "$ns: continuous WAL archiving working" || fail "$ns: ContinuousArchiving is '${st:-missing}'"
done

echo "Policy (Ticket 1.4)"
shopt -s nullglob
bad_files=("$G"/tests/policy/bad/*.yaml); good_files=("$G"/tests/policy/good/*.yaml)
(( ${#bad_files[@]} >= 3 )) || fail "expected at least 3 manifests in tests/policy/bad/"
for f in "${bad_files[@]}"; do
  if remote "kubectl --context kind-$CLUSTER apply --dry-run=server -n sv-dev -f -" <"$f" >/dev/null 2>&1; then
    fail "admitted a bad manifest: $(basename "$f")"
  else pass "rejected $(basename "$f")"; fi
done
for f in "${good_files[@]}"; do
  remote "kubectl --context kind-$CLUSTER apply --dry-run=server -n sv-dev -f -" <"$f" >/dev/null 2>&1 \
    && pass "admitted $(basename "$f")" || fail "rejected a good manifest: $(basename "$f")"
done

echo "Stub BFF (Ticket 1.5)"
for env in dev prod; do
  code="$(remote "curl -s -o /dev/null -w '%{http_code}' --resolve $env.sortedvtg.lan:443:127.0.0.1 https://$env.sortedvtg.lan/healthz" || true)"
  [[ "$code" == 200 ]] && pass "$env.sortedvtg.lan/healthz returns 200" || fail "$env.sortedvtg.lan/healthz returned '$code'"
done

echo "Prod gate (T080, ADR-0002)"
gh api "repos/$SV_OWNER/sorted-vintage-gitops/environments/prod" \
  --jq '.protection_rules[] | select(.type=="required_reviewers") | .reviewers | length' 2>/dev/null | grep -qv '^0$' \
  && pass "gitops environment prod has a required reviewer" || fail "gitops environment prod is missing or has no required reviewer"
[[ -f "$G/.github/workflows/prod-gate.yml" ]] && pass "prod-gate workflow present" || fail "missing .github/workflows/prod-gate.yml in gitops"

echo "Jenkins (Ticket 1.7, research R15)"
JUSER="${SV_JENKINS_USER:-ricomillz}"  # the Air's Jenkins account, not the mini's login of the same name
[[ "$(id -un)" != "$JUSER" ]] || fail "run this from your everyday account, not as $JUSER"
dsmemberutil checkmembership -U "$JUSER" -G admin | grep -q 'is not a member' \
  && pass "the Air's $JUSER is a standard account" || fail "the Air's $JUSER is an admin or missing"
[[ -z "$(find "$HOME" -maxdepth 0 -perm -040)" ]] && pass "your home folder is closed to other accounts" \
  || fail "$HOME is group-readable; run chmod 700 ~ (docs/runbooks/jenkins.md, step 0)"
# netstat, not lsof: without sudo, lsof only sees your own processes, and Jenkins runs as another account.
listen="$(netstat -anv -p tcp 2>/dev/null | awk '$4 ~ /[.:]8080$/ && $6 == "LISTEN" {print $4, $11}' | sort -u)"
[[ -n "$listen" ]] || fail "Jenkins is not listening on the Air (sudo launchctl kickstart system/com.sortedvintage.jenkins)"
awk '{print $1}' <<<"$listen" | grep -qv '^127\.0\.0\.1\.' && fail "port 8080 on the Air listens beyond loopback: $(tr '\n' ' ' <<<"$listen")"
pass "Jenkins listens on 127.0.0.1:8080 only"
for pid in $(awk '{n=split($2, a, ":"); print a[n]}' <<<"$listen" | sort -u); do
  [[ "$(ps -o uid= -p "$pid" | tr -d ' ')" == "$(id -u "$JUSER")" ]] || fail "port 8080 is held by PID $pid, which is not the Air's $JUSER"
done
pass "Jenkins runs as the Air's $JUSER"
[[ -r "/Users/$JUSER/.ssh/sv_jenkins_agent" ]] && fail "your everyday account can read the agent key"
pass "the agent key is not readable from your everyday account"
code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/login || true)"
[[ "$code" == 200 ]] && pass "Jenkins answers at localhost:8080" || fail "Jenkins returned '$code'"
remote "grep -q '^restrict .*sv-jenkins-agent@' ~/.ssh/authorized_keys" \
  && pass "the mini authorizes the agent key with restrict" || fail "agent key missing or unrestricted on $MINI (scripts/jenkins/authorize-agent-key.sh)"
remote "export PATH=/opt/homebrew/opt/openjdk@21/bin:\$PATH; java -version" >/dev/null 2>&1 \
  && pass "Java is available for the agent on the mini" || fail "Java is missing on $MINI (openjdk@21)"

echo "SonarQube Cloud (T105)"
gh api "repos/$SV_OWNER/sorted-vintage-app/commits/main/check-runs" --jq '.check_runs[].name' 2>/dev/null | grep -qi sonar \
  && pass "SonarQube Cloud check on sorted-vintage-app main" || fail "no SonarQube Cloud check on the latest sorted-vintage-app main commit"

echo
echo "Sprint 1 verification passed."
echo "Manual checks left: make down / make up in under 10 minutes with Grafana history intact,"
echo "the memory measurement in sprint1_retro.md, an infra-terraform run with a paused approval on the lab agent,"
echo "and the SonarQube Cloud quality gate on a pull request."
