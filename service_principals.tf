# =============================================================================
# Terraform-Managed Service Principals
# =============================================================================
# Service principals created and fully managed by Terraform.
# Pre-existing SPs (looked up via data sources) remain in groups.tf.

locals {
  airflow_service_principals = {
    airflow     = "airflow"
    airflow_dev = "airflow_dev"
  }
}

resource "databricks_service_principal" "airflow" {
  for_each     = local.airflow_service_principals
  provider     = databricks.account
  display_name = each.value
  lifecycle { prevent_destroy = true }
}

# Assign to workspace so they can access workspace-level resources
resource "databricks_mws_permission_assignment" "airflow" {
  for_each     = local.airflow_service_principals
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.airflow[each.key].id
  permissions  = ["USER"]
}

resource "databricks_service_principal" "segment_storage" {
  provider     = databricks.account
  display_name = "segment_storage"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "segment_storage" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.segment_storage.id
  permissions  = ["USER"]
}
