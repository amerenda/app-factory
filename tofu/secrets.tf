# --- Prod database password ---
resource "random_password" "db" {
  length  = 40
  special = false
}

resource "bitwarden-secrets_secret" "db_password" {
  key        = "${var.app_name}-postgres-password"
  value      = random_password.db.result
  project_id = var.bws_project_id
}

# --- UAT database password ---
resource "bitwarden-secrets_secret" "db_password_uat" {
  count      = var.uat_enabled ? 1 : 0
  key        = "${var.app_name}-uat-postgres-password"
  value      = random_password.db_uat[0].result
  project_id = var.bws_project_id
}

# --- Additional auto-generated secrets (session keys, JWT secrets, etc.) ---
resource "random_password" "generated" {
  for_each = { for s in var.secrets : s.bws_name => s if s.generate }
  length   = 40
  special  = false
}

resource "bitwarden-secrets_secret" "generated" {
  for_each   = { for s in var.secrets : s.bws_name => s if s.generate }
  key        = each.key
  value      = random_password.generated[each.key].result
  project_id = var.bws_project_id
}
