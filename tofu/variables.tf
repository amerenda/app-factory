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

variable "postgres_admin_secret_id" {
  description = "BWS secret UUID for the postgres admin password"
  type        = string
  default     = "a280e465-8813-4b48-9972-b4210149cb60" # mini-postgres-password
}

variable "bws_project_id" {
  description = "BWS project UUID for new secrets"
  type        = string
  default     = "6353f589-39c0-45f2-9e9c-b36f00e0c282" # k3s project
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
  description = "Additional secrets to create in BWS (session keys, etc.)"
  type = list(object({
    bws_name = string
    generate = bool
  }))
  default = []
}
