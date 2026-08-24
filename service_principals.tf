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

# dbt Cloud staging service principal for the staging deployment environment
resource "databricks_service_principal" "dbt_cloud_staging" {
  provider     = databricks.account
  display_name = "dbt_cloud_staging"
  lifecycle { prevent_destroy = true }
}

resource "databricks_mws_permission_assignment" "dbt_cloud_staging" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.dbt_cloud_staging.id
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

# Sigma Computing service principal for the BI POV.
# Mart access via group membership in groups.tf;
# dedicated wh-sigma-pov warehouse grant in permissions.tf.
resource "databricks_service_principal" "sigma" {
  provider     = databricks.account
  display_name = "sigma"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "sigma" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.sigma.id
  permissions  = ["USER"]
}

resource "databricks_service_principal" "icp_finder" {
  provider     = databricks.account
  display_name = "icp-finder"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "icp_finder" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.icp_finder.id
  permissions  = ["USER"]
}

# Read-only SP for the analytics governance loop. OAuth secret is manual; see README.
resource "databricks_service_principal" "product_analytics" {
  provider     = databricks.account
  display_name = "product_analytics"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "product_analytics" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.product_analytics.id
  permissions  = ["USER"]
}

# Win and Serve product agent service principals. OAuth M2M credentials generated manually.
resource "databricks_service_principal" "agent" {
  for_each     = local.agent_products
  provider     = databricks.account
  display_name = each.value.sp_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "agent" {
  for_each     = local.agent_products
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.agent[each.key].id
  permissions  = ["USER"]
}

# The gp-api application's read-only principal for direct SQL against its
# mart. OAuth M2M credentials generated manually; see README.
resource "databricks_service_principal" "gp_api" {
  provider     = databricks.account
  display_name = local.gp_api.sp_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "gp_api" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.gp_api.id
  permissions  = ["USER"]
}
