# Account-level groups for Unity Catalog
# These groups must be created at the account level to grant Unity Catalog permissions

# Data sources for service principals (managed outside Terraform)
data "databricks_service_principal" "dbt_cloud" {
  provider     = databricks.account
  display_name = "dbt_cloud"
}

data "databricks_service_principal" "airbyte" {
  provider     = databricks.account
  display_name = "airbyte"
}

data "databricks_service_principal" "ai_infra" {
  provider     = databricks.account
  display_name = "ai-infra"
}

data "databricks_service_principal" "zapier" {
  provider     = databricks.account
  display_name = "zapier"
}

data "databricks_service_principal" "github_action" {
  provider     = databricks.account
  display_name = "github-action"
}

data "databricks_service_principal" "looker_studio" {
  provider     = databricks.account
  display_name = "looker-studio"
}
# Data sources for existing groups (managed outside Terraform)
data "databricks_group" "account_users" {
  provider     = databricks.account
  display_name = "account users"
}

data "databricks_group" "admin_group" {
  provider     = databricks.account
  display_name = "admin group"
}

data "databricks_group" "data_users" {
  provider     = databricks.account
  display_name = "data users"
}

data "databricks_group" "ai_owners" {
  provider     = databricks.account
  display_name = "ai-owners"
}

data "databricks_group" "data_engineers" {
  provider     = databricks.account
  display_name = "data-engineers"
}

data "databricks_group" "dbt_users" {
  provider     = databricks.account
  display_name = "dbt-users"
}

data "databricks_group" "token_users" {
  provider     = databricks.account
  display_name = "token-users"
}

# Dynamic mart reader groups from YAML configuration
resource "databricks_group" "mart_readers_account" {
  for_each = local.marts_map
  provider = databricks.account

  display_name = "mart_${each.key}_readers"

  lifecycle {
    prevent_destroy = true
  }
}

# dbt developers group for day-to-day dbt users
# Can read all mart data
resource "databricks_group" "dbt_developers_account" {
  provider     = databricks.account
  display_name = "dbt_developers"

  lifecycle {
    prevent_destroy = true
  }
}

# Assign account groups to workspace
# This makes the account-level groups visible and usable within the workspace

# Assign mart reader groups to workspace
resource "databricks_mws_permission_assignment" "mart_readers" {
  for_each     = local.marts_map
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.mart_readers_account[each.key].id
  permissions  = ["USER"]
}

# Assign dbt-developers to workspace
resource "databricks_mws_permission_assignment" "dbt_developers" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.dbt_developers_account.id
  permissions  = ["USER"]
}
