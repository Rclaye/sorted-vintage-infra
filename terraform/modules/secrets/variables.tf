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
