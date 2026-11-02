# Bootstrap Secrets, created before Argo CD syncs the apps that read them (plan: Complexity Tracking).
# Values come from the git-ignored secrets.auto.tfvars; they also end up in the local state on the mini.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
  }
}

locals {
  databases = ["listings", "orders", "payments", "notifications"]

  # The environment names are not secret, only the values are; for_each cannot take sensitive keys.
  env_names = nonsensitive(toset(keys(var.environments)))

  # One entry per environment and database, e.g. "dev/orders".
  db_secrets = {
    for pair in setproduct(local.env_names, local.databases) :
    "${pair[0]}/${pair[1]}" => { env = pair[0], db = pair[1] }
  }
}

resource "kubernetes_namespace_v1" "env" {
  for_each = local.env_names

  metadata {
    name = "sv-${each.key}"
  }
}

resource "kubernetes_namespace_v1" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "kubernetes_secret_v1" "stripe" {
  for_each = local.env_names

  metadata {
    name      = "stripe"
    namespace = kubernetes_namespace_v1.env[each.key].metadata[0].name
  }

  data = {
    "secret-key"      = var.environments[each.key].stripe_secret_key
    "publishable-key" = var.environments[each.key].stripe_publishable_key
    "webhook-secret"  = var.environments[each.key].stripe_webhook_secret
  }
}

# Fixed passwords, so a cluster restored from backup still matches the roles inside the database.
resource "kubernetes_secret_v1" "db" {
  for_each = local.db_secrets

  metadata {
    name      = "pg-${each.value.db}-app"
    namespace = kubernetes_namespace_v1.env[each.value.env].metadata[0].name
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = each.value.db
    password = var.environments[each.value.env].db_passwords[each.value.db]
  }
}

resource "kubernetes_secret_v1" "tls" {
  metadata {
    name      = "sortedvtg-lan-tls"
    namespace = kubernetes_namespace_v1.ingress_nginx.metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.tls_certificate
    "tls.key" = var.tls_private_key
  }
}
