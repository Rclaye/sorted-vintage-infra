#!/bin/bash
# Run a terraform plan and print only its summary: which resources change and the Plan line.
# The Kind provider does not mark the cluster's client key and kubeconfig sensitive, so a plan
# that destroys or replaces the cluster prints them in full; Jenkins kept them in build 43's log
# (2026-11-20). The full plan goes to a private temporary file that is deleted afterwards; on a
# failed plan only the error lines are printed. Keeps terraform's exit code (-detailed-exitcode
# still works).
#   scripts/lab/quiet-plan.sh -chdir=terraform/cluster plan -no-color -destroy -out=cluster.tfplan
set -uo pipefail
log=$(mktemp "${TMPDIR:-/tmp}/quiet-plan.XXXXXX")
trap 'rm -f "$log"' EXIT
chmod 600 "$log"
terraform "$@" >"$log" 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
  grep -E '^(Error|│ Error|Warning)|^ +on |^ +[0-9]+:' "$log" | grep -v -i -E 'BEGIN|PRIVATE|client-key|certificate' || echo "terraform plan failed (no error lines found)"
else
  grep -E '^  # .* (will be|must be)|^Plan:|^No changes' "$log"
fi
exit "$rc"
