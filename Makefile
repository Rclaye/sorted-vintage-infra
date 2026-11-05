# Lab sessions on the Mac mini (T013, FR-018, FR-024). Run as bot from this repo:
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

.PHONY: help up down backups-check rebuild destroy status

help:
	@sed -n '2,8s/^# //p' Makefile

up:
	@scripts/lab/up.sh

down:
	@scripts/lab/down.sh

backups-check:
	@DRY_RUN=1 scripts/lab/down.sh

rebuild:
	@. scripts/lab/common.sh && require_lab_user && require_docker
	$(TF) -chdir=terraform/cluster init -input=false
	$(TF) -chdir=terraform/cluster apply
	$(TF) -chdir=terraform/bootstrap init -input=false
	$(TF) -chdir=terraform/bootstrap apply
	@scripts/lab/rebuild-wait.sh

destroy:
	@. scripts/lab/common.sh && require_lab_user && require_docker
	$(TF) -chdir=terraform/bootstrap destroy
	$(TF) -chdir=terraform/cluster destroy
	@echo "Garage data in ~/sv-data is kept (photos and backups survive a rebuild)."

status:
	@. scripts/lab/common.sh && docker ps -a --filter "name=$$NODE" --format "{{.Names}}  {{.Status}}" && k -n argocd get applications.argoproj.io 2>/dev/null || echo "API not reachable (node stopped?)"
