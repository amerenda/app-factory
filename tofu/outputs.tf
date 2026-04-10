output "database_name" {
  description = "PostgreSQL database name"
  value       = postgresql_database.app.name
}

output "database_role" {
  description = "PostgreSQL role name"
  value       = postgresql_role.app.name
}

output "database_extensions" {
  description = "Enabled PostgreSQL extensions"
  value       = [for ext in postgresql_extension.app : ext.name]
}

output "db_password_bws_id" {
  description = "BWS secret ID for the database password"
  value       = bitwarden-secrets_secret.db_password.id
}

output "generated_secret_ids" {
  description = "BWS secret IDs for auto-generated secrets"
  value       = { for k, v in bitwarden-secrets_secret.generated : k => v.id }
}
