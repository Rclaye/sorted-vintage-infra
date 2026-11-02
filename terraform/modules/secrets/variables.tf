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
