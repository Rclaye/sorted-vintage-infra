# A record of the first infra-terraform run that paused for approval and applied (Ticket 1.7
# acceptance). terraform_data lives only in Terraform state: it creates nothing in the cluster or
# on the lab host. Changing `input` gives the pipeline a harmless change to approve again later.
resource "terraform_data" "pipeline_approval_check" {
  input = "2026-11-05: first approved apply through Jenkins"
}
