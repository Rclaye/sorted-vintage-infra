# Bootstrap Secrets, created before Argo CD syncs the apps that read them (plan: Complexity Tracking).
# Values come from the git-ignored secrets.auto.tfvars; they also end up in the local state on the mini.

terraform {
  required_providers {
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

# Observability (T019): the namespace exists before Argo CD syncs the stack, because Grafana's
# admin Secret has to be in it. The password is generated here and never committed; the chart's
# well-known default is never used. Read it with:
#   kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin.result
  }
}

# Keycloak (T025, research R16): one instance with a realm per environment, in its own namespace with
# its own Postgres (keycloak-db). The database password is fixed, so a restored keycloak-db still
# matches it; client secrets are fixed, so the realms and the services that use them always agree.
resource "kubernetes_namespace_v1" "keycloak" {
  metadata {
    name = "keycloak"
  }
}

resource "kubernetes_secret_v1" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
  }

  data = {
    username = "admin"
    password = var.keycloak.admin_password
  }
}

resource "kubernetes_secret_v1" "keycloak_db" {
  metadata {
    name      = "pg-keycloak-app"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = "keycloak"
    password = var.keycloak.db_password
  }
}

# keycloak-db archives to the prod Garage (R16), with prod's backups key.
resource "kubernetes_secret_v1" "keycloak_s3_backups" {
  metadata {
    name      = "s3-backups"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
  }

  data = {
    "ACCESS_KEY_ID"     = var.garage["prod"].backups_key_id
    "ACCESS_SECRET_KEY" = var.garage["prod"].backups_secret_key
  }
}

# The realm import reads these as environment variables (${SV_DEV_BFF_SECRET} and so on).
resource "kubernetes_secret_v1" "keycloak_realm_clients" {
  metadata {
    name      = "keycloak-realm-clients"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
  }

  data = merge(
    merge([
      for env in ["dev", "prod"] : {
        for c in ["bff", "orders", "payments", "listings"] :
        "SV_${upper(env)}_${upper(c)}_SECRET" => var.keycloak.clients[env][c]
      }
    ]...),
    { SV_DEV_SEED_SECRET = random_password.keycloak_dev_seed.result },
  )
}

# The same client secrets where each environment's services read them.
resource "kubernetes_secret_v1" "keycloak_clients" {
  for_each = local.env_names

  metadata {
    name      = "keycloak-clients"
    namespace = kubernetes_namespace_v1.env[each.key].metadata[0].name
  }

  data = merge(
    { for c in ["bff", "orders", "payments", "listings"] : c => var.keycloak.clients[each.key][c] },
    each.key == "dev" ? { seed = random_password.keycloak_dev_seed.result } : {},
  )
}

# sv-dev only (T120, Sprint 2 spikes "Script token"): the seed client, a service account that may
# only manage users, through which the seed job (T051) creates the demo sellers and the verify
# seller. Generated here like Grafana's admin password, so secrets.auto.tfvars does not change.
resource "random_password" "keycloak_dev_seed" {
  length  = 32
  special = false
}

# The one sv-dev user that verify_sprint2.sh (T115) signs in as, through the BFF login form like a
# browser. The seed job creates the user with this password; the user is never in a realm file.
resource "random_password" "dev_verify_seller" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "dev_verify_seller" {
  metadata {
    name      = "verify-seller"
    namespace = kubernetes_namespace_v1.env["dev"].metadata[0].name
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = "verify-seller@sortedvtg.lan"
    password = random_password.dev_verify_seller.result
  }
}
