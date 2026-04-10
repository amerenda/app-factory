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
