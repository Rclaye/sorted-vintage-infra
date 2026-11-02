variable "name" {
  description = "Kind cluster name; the kubeconfig context is kind-<name>."
  type        = string
  default     = "sorted-vintage"
}

variable "node_image" {
  description = "kindest/node image, pinned by digest so a rebuild never pulls a different node."
  type        = string
}

variable "ingress_listen_address" {
  description = "Host address for ports 80 and 443. Loopback until Tailscale exists, then the mini's Tailscale IP (research R2)."
  type        = string
  default     = "127.0.0.1"

  validation {
    condition     = var.ingress_listen_address != "0.0.0.0"
    error_message = "Binding ingress to 0.0.0.0 exposes the lab on the home network (Principle VI)."
  }
}

variable "lab_data_dir" {
  description = "Host directory mounted into the node at /var/lab-data for Garage data (photos and backups)."
  type        = string
  default     = "~/sv-data"
}
