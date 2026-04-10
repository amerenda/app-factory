variable "postgres_host" {
  description = "PostgreSQL server hostname"
  type        = string
  default     = "agent-kb.amer.dev"
}

variable "postgres_port" {
  description = "PostgreSQL server port"
  type        = number
  default     = 5432
}

variable "postgres_admin_user" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "postgres"
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password (fetched from BWS)"
  type        = string
  sensitive   = true
}

variable "secrets_api_url" {
  description = "Secrets API base URL"
  type        = string
  default     = "http://10.100.20.18:8090"
}

variable "secrets_api_token" {
  description = "Bearer token for secrets API"
  type        = string
  sensitive   = true
}

variable "app_name" {
  description = "Application name (kebab-case)"
  type        = string
}

variable "app_db_extensions" {
  description = "PostgreSQL extensions to enable"
  type        = list(string)
  default     = []
}

variable "secrets" {
  description = "Secrets to create via the secrets API"
  type = list(object({
    bws_name  = string
    generate  = bool
  }))
  default = []
}
