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
