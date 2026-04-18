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
      version = "~> 0.1"
    }
  }

  # GCS backend — authenticates via GOOGLE_CREDENTIALS env var or
  # application default credentials (gcloud auth application-default login).
  backend "gcs" {
    bucket = "amerenda-tofu-state"
    prefix = "dean/app-factory"
  }
}

# BWS provider — reads/writes secrets in Bitwarden Secrets Manager.
# Authenticates via BWS_ACCESS_TOKEN env var.
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
