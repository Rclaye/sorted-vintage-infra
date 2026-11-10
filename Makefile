# Lab sessions on the lab host (T013, FR-018, FR-024). Run as bot from this repo:
#   make up       start a session: Kind node up, wait until every Argo CD app is Synced/Healthy
#   make down     end a session: read-only check that Postgres archives are current, then stop
#   make rebuild  terraform apply for cluster then bootstrap, then wait for health (one command,
#                 constitution Principle II); terraform asks before applying
#   make destroy  terraform destroy for bootstrap then cluster; Garage data in ~/sv-data is kept
#   make status   show the node and the Argo CD apps
#   make backups-check  the make down checks without stopping anything
SHELL := /bin/bash
.DEFAULT_GOAL := help
TF := terraform

.PHONY: help up down backups-check tf-init rebuild destroy status

help:
	@sed -n '2,8s/^# //p' Makefile

up:
	@scripts/lab/up.sh

down:
	@scripts/lab/down.sh

backups-check:
	@DRY_RUN=1 scripts/lab/down.sh

# Terraform state and secrets.auto.tfvars live in bot's private folder, outside any clone, so
# make rebuild and the Jenkins pipeline use the same ones.
SV_TF_DIR ?= $(HOME)/sv-terraform
TF_CLUSTER := -chdir=terraform/cluster
TF_BOOT := -chdir=terraform/bootstrap
BOOT_VARS := -var cluster_state_path=$(SV_TF_DIR)/cluster.tfstate -var-file=$(SV_TF_DIR)/secrets.auto.tfvars

tf-init:
	@test -f $(SV_TF_DIR)/secrets.auto.tfvars || { echo "missing $(SV_TF_DIR)/secrets.auto.tfvars (scripts/secrets/new-secrets-tfvars.sh)"; exit 1; }
	$(TF) $(TF_CLUSTER) init -input=false -backend-config=path=$(SV_TF_DIR)/cluster.tfstate
	$(TF) $(TF_BOOT) init -input=false -backend-config=path=$(SV_TF_DIR)/bootstrap.tfstate

rebuild:
	@. scripts/lab/common.sh && require_lab_user && require_docker
	@$(MAKE) --no-print-directory tf-init
	$(TF) $(TF_CLUSTER) apply
	$(TF) $(TF_BOOT) apply $(BOOT_VARS)
	@scripts/lab/rebuild-wait.sh

destroy:
	@. scripts/lab/common.sh && require_lab_user && require_docker
	@$(MAKE) --no-print-directory tf-init
	$(TF) $(TF_BOOT) destroy $(BOOT_VARS)
	$(TF) $(TF_CLUSTER) destroy
	@echo "Garage data in ~/sv-data is kept (photos and backups survive a rebuild)."

status:
	@. scripts/lab/common.sh && docker ps -a --filter "name=$$NODE" --format "{{.Names}}  {{.Status}}" && k -n argocd get applications.argoproj.io 2>/dev/null || echo "API not reachable (node stopped?)"
