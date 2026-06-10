terraform {
  required_version = ">= 1.6.0"

  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    bitwarden-secrets = {
      source  = "bitwarden/bitwarden-secrets"
      version = "0.5.4-pre"
    }
  }

  # Kubernetes backend — state stored as a k8s Secret in the infra-mcp namespace.
  # No external credentials needed; uses the pod's service account.
  backend "kubernetes" {
    secret_suffix = "app-factory"
    namespace     = "infra-mcp"
  }
}

# BWS provider — reads/writes secrets in Bitwarden Secrets Manager.
# Set env vars: BW_ACCESS_TOKEN, BW_API_URL, BW_IDENTITY_API_URL, BW_ORGANIZATION_ID
provider "bitwarden-secrets" {}

# Read the postgres admin password from BWS so we don't need bws CLI.
data "bitwarden-secrets_secret" "postgres_admin" {
  id = var.postgres_admin_secret_id
}

provider "postgresql" {
  host     = var.postgres_host
  port     = var.postgres_port
  username = var.postgres_admin_user
  password = data.bitwarden-secrets_secret.postgres_admin.value
  sslmode  = "disable"
}
