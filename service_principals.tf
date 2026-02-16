# =============================================================================
# Terraform-Managed Service Principals
# =============================================================================
# Service principals created and fully managed by Terraform.
# Pre-existing SPs (looked up via data sources) remain in groups.tf.

resource "databricks_service_principal" "airflow" {
  provider     = databricks.account
  display_name = "airflow"
  lifecycle { prevent_destroy = true }
}

# Assign to workspace so it can access workspace-level resources
resource "databricks_mws_permission_assignment" "airflow" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.airflow.id
  permissions  = ["USER"]
}

