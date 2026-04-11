# --- Prod database ---

resource "postgresql_role" "app" {
  name     = var.app_name
  password = random_password.db.result
  login    = true
}

resource "postgresql_database" "app" {
  name  = var.app_name
  owner = postgresql_role.app.name
}

resource "postgresql_extension" "app" {
  for_each = toset(var.app_db_extensions)
  name     = each.value
  database = postgresql_database.app.name
}

resource "postgresql_grant" "tables" {
  database    = postgresql_database.app.name
  role        = postgresql_role.app.name
  schema      = "public"
  object_type = "table"
  privileges  = ["ALL"]
}

resource "postgresql_grant" "sequences" {
  database    = postgresql_database.app.name
  role        = postgresql_role.app.name
  schema      = "public"
  object_type = "sequence"
  privileges  = ["ALL"]
}

resource "postgresql_default_privileges" "tables" {
  database    = postgresql_database.app.name
  role        = postgresql_role.app.name
  owner       = postgresql_role.app.name
  schema      = "public"
  object_type = "table"
  privileges  = ["ALL"]
}

resource "postgresql_default_privileges" "sequences" {
  database    = postgresql_database.app.name
  role        = postgresql_role.app.name
  owner       = postgresql_role.app.name
  schema      = "public"
  object_type = "sequence"
  privileges  = ["ALL"]
}

# --- UAT database (same instance, separate database + role) ---

resource "random_password" "db_uat" {
  count   = var.uat_enabled ? 1 : 0
  length  = 40
  special = false
}

resource "postgresql_role" "app_uat" {
  count    = var.uat_enabled ? 1 : 0
  name     = "${var.app_name}_uat"
  password = random_password.db_uat[0].result
  login    = true
}

resource "postgresql_database" "app_uat" {
  count = var.uat_enabled ? 1 : 0
  name  = "${var.app_name}_uat"
  owner = postgresql_role.app_uat[0].name
}

resource "postgresql_extension" "app_uat" {
  for_each = var.uat_enabled ? toset(var.app_db_extensions) : toset([])
  name     = each.value
  database = postgresql_database.app_uat[0].name
}

resource "postgresql_default_privileges" "uat_tables" {
  count       = var.uat_enabled ? 1 : 0
  database    = postgresql_database.app_uat[0].name
  role        = postgresql_role.app_uat[0].name
  owner       = postgresql_role.app_uat[0].name
  schema      = "public"
  object_type = "table"
  privileges  = ["ALL"]
}

resource "postgresql_default_privileges" "uat_sequences" {
  count       = var.uat_enabled ? 1 : 0
  database    = postgresql_database.app_uat[0].name
  role        = postgresql_role.app_uat[0].name
  owner       = postgresql_role.app_uat[0].name
  schema      = "public"
  object_type = "sequence"
  privileges  = ["ALL"]
}
