# Push the generated database password to BWS via the secrets API.
# The API returns 409 if the secret already exists (idempotent).
resource "null_resource" "db_password_to_bws" {
  triggers = {
    app_name = var.app_name
    password = random_password.db.result
  }

  provisioner "local-exec" {
    command = <<-EOT
      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" -X POST \
        "${var.secrets_api_url}/secrets" \
        -H "Authorization: Bearer ${var.secrets_api_token}" \
        -H "Content-Type: application/json" \
        -d '{"name": "${var.app_name}-postgres-password", "value": "${random_password.db.result}"}')
      if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
        echo "Secret created or already exists (HTTP $HTTP_CODE)"
        exit 0
      else
        echo "Failed to create secret (HTTP $HTTP_CODE)" >&2
        exit 1
      fi
    EOT
  }
}

# Create additional auto-generated secrets (session keys, etc.)
resource "null_resource" "generated_secrets" {
  for_each = { for s in var.secrets : s.bws_name => s if s.generate }

  provisioner "local-exec" {
    command = <<-EOT
      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" -X POST \
        "${var.secrets_api_url}/secrets" \
        -H "Authorization: Bearer ${var.secrets_api_token}" \
        -H "Content-Type: application/json" \
        -d '{"name": "${each.key}"}')
      if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
        echo "Secret ${each.key}: created or already exists (HTTP $HTTP_CODE)"
        exit 0
      else
        echo "Failed to create secret ${each.key} (HTTP $HTTP_CODE)" >&2
        exit 1
      fi
    EOT
  }
}
