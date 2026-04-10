# App Factory — deploy stateless apps to k3s
#
# Prerequisites:
#   - bws CLI (bitwarden secrets manager)
#   - tofu (OpenTofu)
#   - python3 with jinja2 (pip install -r generate/requirements.txt)
#
# Required env vars:
#   BWS_ACCESS_TOKEN    — Bitwarden Secrets Manager access token
#   SECRETS_API_TOKEN   — bearer token for the secrets API
#
# Usage:
#   make create-app APP=myapp GITOPS_DIR=../k3s-dean-gitops

SHELL := /bin/bash
.ONESHELL:

APP ?=
GITOPS_DIR ?= ../k3s-dean-gitops

# BWS secret names for infrastructure credentials
BWS_POSTGRES_PW_SECRET := mini-postgres-password
BWS_GCS_ACCESS_KEY     := k3s-dean-backups-access-key
BWS_GCS_SECRET_KEY     := k3s-dean-backups-secret-key
BWS_GCS_ENDPOINT       := k3s-dean-backups-endpoint

# Derived
SPEC := apps/$(APP).toml

.PHONY: create-app validate provision generate commit destroy-app list-apps help

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
	$(eval POSTGRES_PW := $(shell bws secret get $(BWS_POSTGRES_PW_SECRET) --access-token "$$BWS_ACCESS_TOKEN" -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])"))
	$(eval GCS_ACCESS := $(shell bws secret get $(BWS_GCS_ACCESS_KEY) --access-token "$$BWS_ACCESS_TOKEN" -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])"))
	$(eval GCS_SECRET := $(shell bws secret get $(BWS_GCS_SECRET_KEY) --access-token "$$BWS_ACCESS_TOKEN" -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])"))
	$(eval GCS_ENDPOINT := $(shell bws secret get $(BWS_GCS_ENDPOINT) --access-token "$$BWS_ACCESS_TOKEN" -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])"))
	$(eval APP_EXTENSIONS := $(shell python3 -c "import tomllib; spec=tomllib.load(open('$(SPEC)','rb')); print(','.join(spec.get('database',{}).get('extensions',[])))"))
	$(eval APP_SECRETS := $(shell python3 -c "\
		import tomllib,json; \
		spec=tomllib.load(open('$(SPEC)','rb')); \
		secrets=[{'bws_name':s['bws_name'],'generate':s['generate']} for s in spec.get('secrets',[])]; \
		print(json.dumps(secrets))" | sed "s/'/\"/g"))
	cd tofu && tofu init \
		-backend-config="access_key=$(GCS_ACCESS)" \
		-backend-config="secret_key=$(GCS_SECRET)" \
		-backend-config="endpoints={s3=\"$(GCS_ENDPOINT)\"}" \
		-reconfigure
	cd tofu && tofu apply \
		-var="postgres_admin_password=$(POSTGRES_PW)" \
		-var="secrets_api_token=$$SECRETS_API_TOKEN" \
		-var="app_name=$(APP)" \
		-var='app_db_extensions=$(if $(APP_EXTENSIONS),[$(shell echo '$(APP_EXTENSIONS)' | sed 's/,/","/g' | sed 's/^/"/;s/$$/"/')],[])' \
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
ifndef SECRETS_API_TOKEN
	$(error SECRETS_API_TOKEN is required)
endif
