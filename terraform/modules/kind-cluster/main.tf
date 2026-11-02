# Single-node Kind cluster for the lab (research R1): the control-plane node also runs workloads,
# because multi-node Kind clusters do not survive docker stop/start.

terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13.0"
    }
  }
}

locals {
  lab_data_dir = pathexpand(var.lab_data_dir)
}

# Docker Desktop cannot bind-mount a host path that does not exist.
resource "terraform_data" "lab_data_dir" {
  input = local.lab_data_dir

  provisioner "local-exec" {
    command = "mkdir -p '${local.lab_data_dir}'"
  }
}

resource "kind_cluster" "this" {
  name           = var.name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # ingress-nginx's Kind deployment schedules onto nodes with this label.
      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      # Loopback only until Tailscale exists (research R2, Principle VI).
      extra_port_mappings {
        container_port = 80
        host_port      = 80
        listen_address = var.ingress_listen_address
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        listen_address = var.ingress_listen_address
        protocol       = "TCP"
      }

      # MinIO data and backups live outside the cluster lifecycle (plan: Backup durability).
      extra_mounts {
        host_path      = terraform_data.lab_data_dir.output
        container_path = "/var/lab-data"
      }
    }
  }
}
