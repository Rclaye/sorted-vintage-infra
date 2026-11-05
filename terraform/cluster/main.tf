# Root 1 of 2: the Kind cluster. Applied before terraform/bootstrap (make rebuild).
# Run on the Mac mini as bot. State stays local and git-ignored.

terraform {
  required_version = ">= 1.11, < 2.0" # applied with 1.17 on the mini and in CI; the Air only validates

  # State lives outside any clone, in bot's private ~/sv-terraform (mode 700), so make rebuild and
  # the Jenkins pipeline share it. The path is given at init:
  #   terraform init -backend-config=path=$HOME/sv-terraform/cluster.tfstate
  backend "local" {}

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13.0"
    }
  }
}

provider "kind" {}

module "kind_cluster" {
  source = "../modules/kind-cluster"

  node_image             = "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"
  ingress_listen_address = var.ingress_listen_address
  lab_data_dir           = var.lab_data_dir
}

variable "ingress_listen_address" {
  description = "Host address for ports 80 and 443 (research R2)."
  type        = string
  default     = "127.0.0.1"
}

variable "lab_data_dir" {
  description = "Host directory for Garage data (photos and backups)."
  type        = string
  default     = "~/sv-data"
}

# Read by terraform/bootstrap through terraform_remote_state.
output "name" {
  value = module.kind_cluster.name
}

output "endpoint" {
  value = module.kind_cluster.endpoint
}

output "cluster_ca_certificate" {
  value = module.kind_cluster.cluster_ca_certificate
}

output "client_certificate" {
  value = module.kind_cluster.client_certificate
}

output "client_key" {
  value     = module.kind_cluster.client_key
  sensitive = true
}
