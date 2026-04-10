# App Factory

Pipeline for deploying stateless apps to the k3s cluster. Creates secrets, databases, k8s manifests, and ArgoCD registration from a single TOML spec.

## Prerequisites

- `bws` CLI ([Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-cli/))
- `tofu` ([OpenTofu](https://opentofu.org/docs/intro/install/))
- `python3` with `jinja2` (`pip install -r generate/requirements.txt`)
- `gh` CLI (for creating template repos)

## Quick Start

```bash
# 1. Create a new app repo from the template
gh repo create amerenda/my-app --template amerenda/app-template --public --clone

# 2. Write the app spec
cp apps/quiz.toml apps/my-app.toml
# Edit apps/my-app.toml with your app's config

# 3. Export credentials
export BWS_ACCESS_TOKEN="..."       # from BWS UI → Machine Accounts
export SECRETS_API_TOKEN="..."      # secrets API bearer token

# 4. Run the pipeline
make create-app APP=my-app GITOPS_DIR=../k3s-dean-gitops

# 5. Review and push gitops changes
cd ../k3s-dean-gitops
git add -A && git diff --cached
git commit -m "feat: add my-app via app-factory"
git push

# 6. Install the GitHub App on your new repo
# GitHub → amerenda org → Settings → GitHub Apps → amerenda-deploy-bot → Install on my-app

# 7. Push code to your app repo — CI handles the rest
```

## Commands

| Command | Description |
|---------|-------------|
| `make create-app APP=x` | Full pipeline: validate → provision → generate |
| `make validate APP=x` | Validate the TOML spec |
| `make provision APP=x` | Create secrets + database via OpenTofu |
| `make generate APP=x` | Generate k8s manifests to gitops repo |
| `make destroy-app APP=x` | Remove manifests (does not drop database) |
| `make list-apps` | List all app specs |

## App Spec Format

See `apps/quiz.toml` for a complete reference. Key sections:

- `[app]` — name, domain, namespace
- `[[components]]` — container definitions (image, port, env, resources, health check)
- `[[secrets]]` — BWS secrets mapped to k8s ExternalSecrets
- `[database]` — PostgreSQL database + user + extensions
- `[uat]` — UAT deployment overrides
- `[cicd]` — GitHub repo + deploy label for CI/CD

## What Gets Created

Running `make create-app` produces:

| Output | Location |
|--------|----------|
| PostgreSQL user + database | Mac Mini postgres (via OpenTofu) |
| BWS secrets | Bitwarden Secrets Manager (via secrets API) |
| Deployment + Service (prod) | `k3s-dean-gitops/apps/<app>/<component>/` |
| Deployment + Service (UAT) | `k3s-dean-gitops/apps/<app>/<component>-uat/` |
| ExternalSecret | `k3s-dean-gitops/apps/<app>/<component>/externalsecret.yaml` |
| Ingress | `k3s-dean-gitops/apps/<app>/<component>/ingress.yaml` |
| ARC runner values | `k3s-dean-gitops/infra/arc-runners-<app>/values.yaml` |
| ArgoCD Application | Appended to `root-app.yaml` |
| UAT ApplicationSet entry | Inserted into `uat-applicationset.yaml` |

## Manual Steps After Running

1. **Install GitHub App**: `amerenda-deploy-bot` must be installed on the new app repo for CI to work
2. **Manual secrets**: Secrets with `generate = false` in the spec must be created in BWS manually
3. **Push gitops**: Review the generated manifests, commit, and push to `k3s-dean-gitops`
