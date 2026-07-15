# Account-level groups for Unity Catalog
# These groups must be created at the account level to grant Unity Catalog permissions

# Workspace-level app lookup for Genie Slack Bot
data "databricks_app" "genie_slack_bot" {
  name = "gp-genie-slack-bot"
}

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

# Resolve the account-level SP from the workspace app rather than hard-coding its client ID.
data "databricks_service_principal" "genie_slack_bot" {
  provider       = databricks.account
  application_id = data.databricks_app.genie_slack_bot.app.service_principal_client_id
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

# Principal for the Machine Learning Compute single-user cluster
data "databricks_group" "ml_users" {
  provider     = databricks.account
  display_name = "ml-users"
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

# Add Airflow service principals to token-users group
resource "databricks_group_member" "airflow_token_users" {
  for_each  = local.airflow_service_principals
  provider  = databricks.account
  group_id  = data.databricks_group.token_users.id
  member_id = databricks_service_principal.airflow[each.key].id
}

# The Machine Learning Compute cluster runs as the ml-users principal.
# Nesting it into data users grants the same read access analysts have,
# including USE_SCHEMA + SELECT on the dbt schema.
resource "databricks_group_member" "ml_users_in_data_users" {
  provider  = databricks.account
  group_id  = data.databricks_group.data_users.id
  member_id = data.databricks_group.ml_users.id
}

# Give all data users read access to the general-purpose marts.
# mban2026 is excluded (see local.shared_marts).
resource "databricks_group_member" "data_users_in_mart_readers" {
  for_each  = local.shared_marts
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account[each.key].id
  member_id = data.databricks_group.data_users.id
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

# Genie Civics Beta group - members added manually in console
resource "databricks_group" "genie_civics" {
  provider     = databricks.account
  display_name = "genie_civics"

  lifecycle {
    prevent_destroy = true
  }
}

# Add genie_civics as a member of mart_civics_readers
resource "databricks_group_member" "genie_civics_in_mart_civics_readers" {
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account["civics"].id
  member_id = databricks_group.genie_civics.id
}

# Add genie-slack-bot SP to genie_civics group
# Inherits: USE_CATALOG (via mart_civics_readers → catalog_main),
#           USE_SCHEMA + SELECT (via mart_civics_readers → mart_schemas)
resource "databricks_group_member" "genie_slack_bot_in_genie_civics" {
  provider  = databricks.account
  group_id  = databricks_group.genie_civics.id
  member_id = data.databricks_service_principal.genie_slack_bot.id
}

# Add sigma SP to mart reader groups for the POV test cases.
# Inherits: USE_CATALOG (via catalog_main),
#           USE_SCHEMA + SELECT (via mart_schemas)
# SQL warehouse CAN_USE on wh-sigma-pov is granted in permissions.tf.
resource "databricks_group_member" "sigma_in_mart_civics_readers" {
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account["civics"].id
  member_id = databricks_service_principal.sigma.id
}

resource "databricks_group_member" "sigma_in_mart_analytics_readers" {
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account["analytics"].id
  member_id = databricks_service_principal.sigma.id
}

# Analytics governance loop reads its three amplitude tables through mart_analytics;
# reader-group membership grants USE_SCHEMA + SELECT on the mart schema and USE_CATALOG,
# so there are no per-relation grants to break when dbt rebuilds the models.
resource "databricks_group_member" "product_analytics_in_mart_analytics_readers" {
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account["analytics"].id
  member_id = databricks_service_principal.product_analytics.id
}

resource "databricks_group_member" "icp_finder_in_mart_civics_readers" {
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account["civics"].id
  member_id = databricks_service_principal.icp_finder.id
}

# Each product agent SP reads only its own mart, via that mart's reader group.
resource "databricks_group_member" "agent_in_mart_readers" {
  for_each  = local.agent_products
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account[each.value.mart].id
  member_id = databricks_service_principal.agent[each.key].id
}

# The mart_sales_reverse_etl_readers group (generated by the mart_readers_account
# for_each from config/marts.yaml) is intentionally NOT in local.shared_marts:
# mart_sales_reverse_etl holds PII-bearing candidate export feeds, so the "data users"
# group is not auto-added. Membership is managed in the Databricks console (biz-ops).
# When DATA-1840 creates the reverse-ETL service principal, add it here as a
# databricks_group_member of mart_readers_account["sales_reverse_etl"] (unless it is an
# Airflow SP, which already inherits catalog-level SELECT).

# Assign account groups to workspace
# This makes the account-level groups visible and usable within the workspace

# Assign genie_civics to workspace
resource "databricks_mws_permission_assignment" "genie_civics" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.genie_civics.id
  permissions  = ["USER"]
}

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
