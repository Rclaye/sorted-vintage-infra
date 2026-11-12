# Root 2 of 2: Argo CD, the root Application and the bootstrap Secrets. Applied after terraform/cluster.
# Run on the lab host as bot. Needs ~/sv-terraform/secrets.auto.tfvars (scripts/secrets/new-secrets-tfvars.sh),
# passed with -var-file; make rebuild and the Jenkinsfile do that.

terraform {
  required_version = ">= 1.11, < 2.0" # applied with 1.17 on the lab host and in CI; the workstation only validates

  # State in bot's private ~/sv-terraform, like the cluster root:
  #   terraform init -backend-config=path=$HOME/sv-terraform/bootstrap.tfstate
  backend "local" {}

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# Credentials come from the cluster root's local state, not from ~/.kube/config.
data "terraform_remote_state" "cluster" {
  backend = "local"

  config = {
    path = var.cluster_state_path
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
  keycloak        = var.keycloak
  seed_sellers    = var.seed_sellers
  tls_certificate = var.tls_certificate
  tls_private_key = var.tls_private_key
}

variable "cluster_state_path" {
  description = "Path of the cluster root's state, e.g. /Users/bot/sv-terraform/cluster.tfstate."
  type        = string
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

variable "keycloak" {
  description = "Keycloak admin and database passwords and client secrets. Set in secrets.auto.tfvars (scripts/secrets/add-keycloak-secrets.sh)."
  type = object({
    admin_password = string
    db_password    = string
    clients        = map(map(string))
  })
  sensitive = true
}

variable "seed_sellers" {
  description = "sv-dev demo sellers for the seed job (T051): seller key => id of the Stripe test account onboarded by hand for that seller. Set in secrets.auto.tfvars; empty until the accounts exist."
  type        = map(string)
  default     = {}
  sensitive   = true
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
