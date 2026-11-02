# Argo CD and the one Application that hands the cluster to Git (ADR-0002).
# Everything after this is declared in sorted-vintage-gitops and synced by Argo CD.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "oci://ghcr.io/argoproj/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    configs = {
      params = {
        # TLS terminates at ingress-nginx with the mkcert certificate (Ticket 1.3).
        "server.insecure" = true
      }
    }
    dex           = { enabled = false }
    notifications = { enabled = false }
  })]
}

# The root Application comes from the argocd-apps chart rather than a kubernetes_manifest,
# because Terraform cannot plan a custom resource before Argo CD's CRDs exist.
resource "helm_release" "root_app" {
  name       = "argocd-root"
  repository = "oci://ghcr.io/argoproj/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "bootstrap"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
