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

  # GCS backend via S3-compatible API, authenticated with HMAC keys.
  # Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars.
  backend "s3" {
    bucket = "amerenda-tofu-state"
    key    = "dean/app-factory/terraform.tfstate"
    endpoints = {
      s3 = "https://storage.googleapis.com"
    }
    region = "auto"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
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
