variable "environments" {
  description = "Per environment (dev, prod): Stripe test keys from its own sandbox and one password per database."
  type = map(object({
    stripe_secret_key      = string
    stripe_publishable_key = string
    stripe_webhook_secret  = string
    db_passwords           = map(string)
  }))
  sensitive = true

  validation {
    condition     = alltrue([for e in values(var.environments) : startswith(e.stripe_secret_key, "sk_test_") && startswith(e.stripe_publishable_key, "pk_test_")])
    error_message = "Only Stripe test-mode keys (sk_test_, pk_test_) are allowed in the lab."
  }

  validation {
    condition     = alltrue([for e in values(var.environments) : alltrue([for db in ["listings", "orders", "payments", "notifications"] : length(lookup(e.db_passwords, db, "")) >= 20])])
    error_message = "Each environment needs a password of at least 20 characters for listings, orders, payments and notifications."
  }
}

variable "tls_certificate" {
  description = "mkcert certificate for *.sortedvtg.lan (PEM)."
  type        = string
  sensitive   = true
}

variable "tls_private_key" {
  description = "Private key for the mkcert certificate (PEM)."
  type        = string
  sensitive   = true
}

variable "garage" {
  description = "Per environment (dev, prod): Garage's RPC secret and admin token, and the S3 keys the setup Job imports (research R19)."
  type = map(object({
    rpc_secret         = string
    admin_token        = string
    photos_key_id      = string
    photos_secret_key  = string
    backups_key_id     = string
    backups_secret_key = string
  }))
  sensitive = true

  validation {
    condition = alltrue([for g in values(var.garage) :
      can(regex("^[0-9a-f]{64}$", g.rpc_secret)) &&
      length(g.admin_token) >= 32 &&
      can(regex("^GK[0-9a-f]{24}$", g.photos_key_id)) && can(regex("^[0-9a-f]{64}$", g.photos_secret_key)) &&
      can(regex("^GK[0-9a-f]{24}$", g.backups_key_id)) && can(regex("^[0-9a-f]{64}$", g.backups_secret_key))
    ])
    error_message = "Garage needs a 64-hex-character RPC secret, an admin token of 32+ characters, key IDs of the form GK + 24 hex characters, and 64-hex-character secret keys."
  }
}

variable "keycloak" {
  description = "Keycloak's bootstrap admin password, keycloak-db password, and per realm (dev, prod) the client secrets for bff, orders, payments and listings (T025)."
  type = object({
    admin_password = string
    db_password    = string
    clients        = map(map(string))
  })
  sensitive = true

  validation {
    condition = (
      length(var.keycloak.admin_password) >= 32 && length(var.keycloak.db_password) >= 32 &&
      alltrue([for env in ["dev", "prod"] : alltrue([for c in ["bff", "orders", "payments", "listings"] :
      length(lookup(lookup(var.keycloak.clients, env, {}), c, "")) >= 32])])
    )
    error_message = "Keycloak needs admin and database passwords of 32+ characters and a 32+ character secret for bff, orders, payments and listings in both dev and prod."
  }
}

variable "seed_sellers" {
  description = "sv-dev demo sellers for the seed job (T051): seller key (the email's local part, e.g. demo-seller-1 or verify-seller) => the id of the Stripe test account onboarded by hand for that seller. Empty until the accounts exist."
  type        = map(string)
  default     = {}
  sensitive   = true

  validation {
    condition = alltrue([
      for key, account in var.seed_sellers :
      can(regex("^[a-z0-9][a-z0-9-]{1,40}$", key)) && can(regex("^acct_[A-Za-z0-9]{8,64}$", account))
    ])
    error_message = "Each seed seller needs a key of lowercase letters, digits and hyphens, and a Stripe account id of the form acct_..."
  }

  validation {
    condition     = length(distinct(values(var.seed_sellers))) == length(var.seed_sellers)
    error_message = "Each seed seller needs its own Stripe account: an account id appears twice."
  }
}
