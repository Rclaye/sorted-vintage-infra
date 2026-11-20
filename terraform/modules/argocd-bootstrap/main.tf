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

locals {
  # Ready True: Healthy. Otherwise Progressing with the operator's message, so a sync wave keeps
  # waiting while the operator retries (it does, with backoff) rather than failing the sync.
  topology_health = <<-EOT
    hs = { status = "Progressing", message = "waiting for the topology operator" }
    if obj.status ~= nil and obj.status.conditions ~= nil then
      for _, c in ipairs(obj.status.conditions) do
        if c.type == "Ready" then
          if c.status == "True" and (obj.status.observedGeneration == nil or obj.status.observedGeneration >= obj.metadata.generation) then
            hs.status = "Healthy"
            hs.message = ""
          elseif c.message ~= nil and c.message ~= "" then
            hs.message = c.message
          end
        end
      end
    end
    return hs
  EOT
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
        # RabbitMQ users and permissions (Messaging Topology Operator) are Healthy only once the
        # operator has declared them (condition Ready). Argo CD has no built-in check, so they
        # counted as Healthy at once: the User's earlier sync wave did not wait, and a Permission
        # that failed (vhost_or_user_not_found, rebuild drill 2026-11-20) left its app looking
        # Healthy while the operator backed off for up to 16 minutes.
        "resource.customizations.health.rabbitmq.com_User"       = local.topology_health
        "resource.customizations.health.rabbitmq.com_Permission" = local.topology_health
      }
    }
    # Metrics Services only; the ServiceMonitor lives in Git (gitops platform/argocd/monitoring),
    # because its CRD arrives with kube-prometheus-stack after Terraform has finished (T111).
    controller    = { metrics = { enabled = true } }
    server        = { metrics = { enabled = true } }
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
