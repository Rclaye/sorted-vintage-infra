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
        # TLS terminates at Traefik with the mkcert certificate (research R18).
        "server.insecure" = true
        # A sync that waits on a wave that never turns Healthy fails after 10 minutes instead of
        # running forever and blocking every later commit (seen on 2026-11-01 with Traefik).
        "controller.sync.timeout.seconds" = 600
      }
      cm = {
        # Report a child Application's own health, so sync waves in the root app-of-apps wait for it.
        "resource.customizations.health.argoproj.io_Application" = <<-EOT
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil and obj.status.health ~= nil then
            hs.status = obj.status.health.status
            if obj.status.health.message ~= nil then
              hs.message = obj.status.health.message
            end
          end
          return hs
        EOT
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
