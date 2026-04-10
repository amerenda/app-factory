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

  # GCS via S3-compatible HMAC auth.
  # Set env vars: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_S3_ENDPOINT
  # (or pass via -backend-config at init time)
  backend "s3" {
    bucket                      = "amerenda-db-backups"
    key                         = "tofu/app-factory/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
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
