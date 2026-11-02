variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version."
  type        = string
}

variable "gitops_repo_url" {
  description = "Repository the root Application syncs."
  type        = string
  default     = "https://github.com/Rclaye/sorted-vintage-gitops.git"
}

variable "gitops_revision" {
  description = "Branch the root Application follows."
  type        = string
  default     = "main"
}
