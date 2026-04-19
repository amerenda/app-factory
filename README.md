# App Factory

Pipeline for deploying stateless apps to the k3s cluster. Creates secrets, databases, k8s manifests, and ArgoCD registration from a single TOML spec.

## Prerequisites

- `tofu` ([OpenTofu](https://opentofu.org/docs/intro/install/))
- `bws` ([Bitwarden Secrets CLI](https://bitwarden.com/help/secrets-manager-cli/))
- `python3` with `jinja2` (`pip install jinja2`)
- `gh` CLI (for creating template repos)

## Environment Variables

```bash
export BWS_ACCESS_TOKEN="..."       # BWS machine account token (read/write)
export GOOGLE_CREDENTIALS="..."     # Path to GCS service account key JSON (for tofu state)
```

## Quick Start

```bash
# 1. Create a new app repo from the template
gh repo create amerenda/my-app --template amerenda/app-template --public --clone

# 2. Write the app spec
cd app-factory
cp apps/template.toml.example apps/my-app.toml
# Edit apps/my-app.toml with your app's config

# 3. Run the pipeline
make create-app APP=my-app

# 4. Review and push gitops changes
cd ../k3s-dean-gitops
git add -A && git diff --cached
git commit -m "feat: add my-app via app-factory"
git push

# 5. Install the GitHub App on your new repo
# GitHub → amerenda org → Settings → GitHub Apps → amerenda-deploy-bot → Install on my-app

# 6. Push code to your app repo — CI handles the rest
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

`GITOPS_DIR` defaults to `../k3s-dean-gitops`. Override with `make create-app APP=x GITOPS_DIR=/path/to/gitops`.

## App Spec Format

See `apps/template.toml.example` for a starter template, or `apps/quiz.toml` for a complete production example.

### `[app]` (required)

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | yes | — | App name, kebab-case |
| `domain` | yes | — | Domain (e.g. `my-app.amer.dev`) |
| `namespace` | no | same as `name` | k8s namespace |

### `[[components]]` (required, one or more)

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | yes | — | Component name (e.g. `backend`, `frontend`) |
| `image` | yes | — | Docker image (e.g. `amerenda/my-app:backend-latest`) |
| `port` | yes | — | Container port (1-65535) |
| `replicas` | yes | — | Prod replica count |
| `health_path` | yes | — | Health check probe path (e.g. `/health`) |
| `ingress` | no | `false` | `true` generates Ingress + TLS cert + DNS endpoint |

#### `[components.resources]` (required)

```toml
[components.resources.requests]
cpu = "50m"
memory = "64Mi"

[components.resources.limits]
cpu = "200m"
memory = "128Mi"
```

#### `[[components.env]]` (optional, zero or more)

Plain value:
```toml
[[components.env]]
name = "APP_ORIGIN"
value = "https://my-app.amer.dev"
```

Secret reference:
```toml
[[components.env]]
name = "DB_PASSWORD"
secret_ref = { name = "postgres-credentials", key = "password" }
```

### `[[secrets]]` (optional, zero or more)

| Field | Required | Description |
|-------|----------|-------------|
| `bws_name` | yes | BWS secret name (should start with `<app>-`) |
| `k8s_secret` | yes | k8s Secret name (created by ExternalSecret) |
| `k8s_key` | yes | Key within the k8s Secret |
| `generate` | yes | `true` = OpenTofu generates a random 40-char password. `false` = create manually in BWS first. |

Multiple entries can share the same `k8s_secret` — they're grouped into one ExternalSecret.

### `[database]` (optional)

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `type` | yes | — | Only `postgres` supported |
| `name` | yes | — | Database name (usually matches `app.name`) |
| `host` | yes | — | Postgres host (e.g. `agent-kb.amer.dev`) |
| `extensions` | no | `[]` | Extensions to enable (e.g. `["pgcrypto", "vector"]`) |
| `password_secret` | yes | — | Must reference a `[[secrets]]` entry's `bws_name` |

### `[uat]` (optional)

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `enabled` | yes | — | `true` to generate UAT manifests + database |
| `replicas` | no | `1` | UAT replica count |

```toml
[uat]
enabled = true
replicas = 1

[uat.resources.requests]
cpu = "25m"
memory = "32Mi"

[uat.resources.limits]
cpu = "100m"
memory = "64Mi"
```

### `[cicd]` (optional)

| Field | Required | Description |
|-------|----------|-------------|
| `repo` | yes | GitHub repo (e.g. `amerenda/my-app`) — used for ARC runner config |
| `label` | yes | PR label (e.g. `deploy:my-app`) — used for UAT ApplicationSet |

## What Gets Created

| Resource | Location |
|----------|----------|
| PostgreSQL user + database (prod) | Mac Mini postgres (`agent-kb.amer.dev`) |
| PostgreSQL user + database (UAT) | Same instance, `<app>_uat` |
| BWS secrets (generated) | Bitwarden Secrets Manager |
| Deployment + Service (prod) | `k3s-dean-gitops/apps/<app>/<component>/` |
| Deployment + Service (UAT) | `k3s-dean-gitops/apps/<app>/<component>-uat/` |
| ExternalSecret | `k3s-dean-gitops/apps/<app>/<component>/externalsecret.yaml` |
| Ingress + TLS + DNS | `k3s-dean-gitops/apps/<app>/<component>/ingress.yaml` |
| ARC runner scale set | `k3s-dean-gitops/infra/arc-runners-<app>/values.yaml` |
| ArgoCD Application | Appended to `root-app.yaml` |
| UAT ApplicationSet entry | Inserted into `uat-applicationset.yaml` |

## Architecture

### OpenTofu Providers

| Provider | Purpose |
|----------|---------|
| `bitwarden/bitwarden-secrets` (v0.5.4-pre) | Read/write BWS secrets |
| `cyrilgdn/postgresql` (~1.25) | Create postgres roles, databases, extensions |
| `hashicorp/random` (~3.6) | Generate passwords |

State is stored in GCS (`amerenda-tofu-state` bucket, prefix `dean/app-factory/`).

### Manifest Generation

Python + Jinja2. Templates in `generate/templates/`. Idempotent — re-running overwrites manifests and skips ArgoCD entries that already exist.

## Manual Steps After Running

1. **Install GitHub App**: `amerenda-deploy-bot` must be installed on the new app repo
2. **Manual secrets**: Secrets with `generate = false` must be created in BWS manually
3. **Push gitops**: Review the generated manifests, commit, and push to `k3s-dean-gitops`
