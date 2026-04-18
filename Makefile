# App Factory — deploy stateless apps to k3s
#
# Prerequisites:
#   - tofu (OpenTofu)
#   - python3 with jinja2 (pip install -r generate/requirements.txt)
#
# Required env vars:
#   BWS_ACCESS_TOKEN    — Bitwarden Secrets Manager access token
#                         GCS HMAC credentials are fetched from BWS automatically.
#
# Usage:
#   make create-app APP=myapp GITOPS_DIR=../k3s-dean-gitops

SHELL := /bin/bash
.ONESHELL:

APP ?=
GITOPS_DIR ?= ../k3s-dean-gitops

# Derived
SPEC := apps/$(APP).toml

.PHONY: create-app validate provision generate destroy-app list-apps help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

create-app: _check-app validate provision generate ## Full pipeline: validate → provision → generate manifests
	@echo ""
	@echo "=== App $(APP) created ==="
	@echo "Next steps:"
	@echo "  1. cd $(GITOPS_DIR) && git add -A && git diff --cached"
	@echo "  2. Review the changes, then commit and push"
	@echo "  3. Install amerenda-deploy-bot GitHub App on the app repo"

validate: _check-app ## Validate the app spec
	python3 generate/validate.py $(SPEC)

provision: _check-app _check-env ## Provision secrets + database via OpenTofu
	$(eval APP_EXTENSIONS := $(shell python3 -c "import tomllib; spec=tomllib.load(open('$(SPEC)','rb')); exts=spec.get('database',{}).get('extensions',[]); print(' '.join(exts))"))
	$(eval UAT_ENABLED := $(shell python3 -c "import tomllib; spec=tomllib.load(open('$(SPEC)','rb')); print(str(spec.get('uat',{}).get('enabled',False)).lower())"))
	$(eval APP_SECRETS := $(shell python3 -c "\
		import tomllib,json; \
		spec=tomllib.load(open('$(SPEC)','rb')); \
		secrets=[{'bws_name':s['bws_name'],'generate':s['generate']} for s in spec.get('secrets',[])]; \
		print(json.dumps(secrets))"))
	$(eval export AWS_ACCESS_KEY_ID := $(shell bws secret get 7fc1f26c-7145-4b61-b6a9-b43001602096 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['value'])"))
	$(eval export AWS_SECRET_ACCESS_KEY := $(shell bws secret get 2228286b-9f08-4b39-9691-b43001603859 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['value'])"))
	$(eval export AWS_S3_ENDPOINT := https://storage.googleapis.com)
	cd tofu && tofu init -reconfigure
	cd tofu && tofu apply \
		-var="app_name=$(APP)" \
		-var="uat_enabled=$(UAT_ENABLED)" \
		$(if $(APP_EXTENSIONS),$(foreach ext,$(APP_EXTENSIONS),-var="app_db_extensions=[\"$(ext)\"]")) \
		-var='secrets=$(APP_SECRETS)' \
		-auto-approve

generate: _check-app ## Generate k8s manifests and write to gitops repo
	python3 generate/generate.py $(SPEC) $(GITOPS_DIR)

destroy-app: _check-app _check-env ## Remove app infrastructure (does NOT drop the database)
	@echo "WARNING: This will remove generated manifests from $(GITOPS_DIR)"
	@echo "The database will NOT be dropped — do that manually if needed."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	rm -rf $(GITOPS_DIR)/apps/$(APP)/
	rm -rf $(GITOPS_DIR)/infra/arc-runners-$(APP)/
	@echo "Removed manifest directories."
	@echo "TODO: Manually remove ArgoCD entries from root-app.yaml and uat-applicationset.yaml"

list-apps: ## List all app specs
	@ls -1 apps/*.toml 2>/dev/null | sed 's|apps/||;s|\.toml||' || echo "No app specs found"

# --- Internal targets ---

_check-app:
ifndef APP
	$(error APP is required. Usage: make <target> APP=myapp)
endif
	@test -f $(SPEC) || (echo "Error: $(SPEC) not found" && exit 1)

_check-env:
ifndef BWS_ACCESS_TOKEN
	$(error BWS_ACCESS_TOKEN is required)
endif
