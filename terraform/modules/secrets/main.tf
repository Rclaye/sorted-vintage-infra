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

# Traefik serves this certificate as its default (research R18).
resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
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
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.tls_certificate
    "tls.key" = var.tls_private_key
  }
}

# Garage per environment (research R19): the server's RPC secret and admin token, and one S3 key
# per consumer. The setup Job imports the keys, so a rebuilt instance keeps the same credentials.
resource "kubernetes_secret_v1" "garage_admin" {
  for_each = local.env_names

  metadata {
    name      = "garage-admin"
    namespace = kubernetes_namespace_v1.env[each.key].metadata[0].name
  }

  data = {
    "rpc-secret"  = var.garage[each.key].rpc_secret
    "admin-token" = var.garage[each.key].admin_token
  }
}

# Listings writes photos with this key.
resource "kubernetes_secret_v1" "s3_photos" {
  for_each = local.env_names

  metadata {
    name      = "s3-photos"
    namespace = kubernetes_namespace_v1.env[each.key].metadata[0].name
  }

  data = {
    "ACCESS_KEY_ID"     = var.garage[each.key].photos_key_id
    "ACCESS_SECRET_KEY" = var.garage[each.key].photos_secret_key
  }
}

# CloudNativePG's Barman Cloud Plugin archives WAL and base backups with this key.
resource "kubernetes_secret_v1" "s3_backups" {
  for_each = local.env_names

  metadata {
    name      = "s3-backups"
    namespace = kubernetes_namespace_v1.env[each.key].metadata[0].name
  }

  data = {
    "ACCESS_KEY_ID"     = var.garage[each.key].backups_key_id
    "ACCESS_SECRET_KEY" = var.garage[each.key].backups_secret_key
  }
}
