# Root 2 of 2: Argo CD, the root Application and the bootstrap Secrets. Applied after terraform/cluster.
# Run on the Mac mini as bot. Needs secrets.auto.tfvars (scripts/secrets/new-secrets-tfvars.sh).

terraform {
  required_version = ">= 1.11, < 2.0" # applied with 1.17 on the mini and in CI; the Air only validates

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
  }
}

# Credentials come from the cluster root's local state, not from ~/.kube/config.
data "terraform_remote_state" "cluster" {
  backend = "local"

  config = {
    path = "${path.module}/../cluster/terraform.tfstate"
  }
}

locals {
  cluster = data.terraform_remote_state.cluster.outputs
}

provider "kubernetes" {
  host                   = local.cluster.endpoint
  cluster_ca_certificate = local.cluster.cluster_ca_certificate
  client_certificate     = local.cluster.client_certificate
  client_key             = local.cluster.client_key
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster.endpoint
    cluster_ca_certificate = local.cluster.cluster_ca_certificate
    client_certificate     = local.cluster.client_certificate
    client_key             = local.cluster.client_key
  }
}

module "argocd_bootstrap" {
  source = "../modules/argocd-bootstrap"

  argocd_chart_version      = "10.11.6"
  argocd_apps_chart_version = "2.0.7"
}

module "secrets" {
  source = "../modules/secrets"

  environments    = var.environments
  garage          = var.garage
  tls_certificate = var.tls_certificate
  tls_private_key = var.tls_private_key
}

variable "environments" {
  description = "Per environment: Stripe test keys and database passwords. Set in secrets.auto.tfvars."
  type = map(object({
    stripe_secret_key      = string
    stripe_publishable_key = string
    stripe_webhook_secret  = string
    db_passwords           = map(string)
  }))
  sensitive = true
}

variable "garage" {
  description = "Per environment: Garage RPC secret, admin token and S3 keys. Set in secrets.auto.tfvars (scripts/secrets/add-garage-secrets.sh)."
  type = map(object({
    rpc_secret         = string
    admin_token        = string
    photos_key_id      = string
    photos_secret_key  = string
    backups_key_id     = string
    backups_secret_key = string
  }))
  sensitive = true
}

variable "tls_certificate" {
  description = "mkcert certificate for *.sortedvtg.lan (PEM). Set in secrets.auto.tfvars."
  type        = string
  sensitive   = true
}

variable "tls_private_key" {
  description = "Private key for the mkcert certificate (PEM). Set in secrets.auto.tfvars."
  type        = string
  sensitive   = true
}
