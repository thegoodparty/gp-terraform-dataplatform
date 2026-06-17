# =============================================================================
# Product Agent Service Principals, Warehouses, and Access
# =============================================================================
# Win and Serve product AI agents query curated marts in Databricks (TDD
# DATA-1977). Each product agent gets:
#   - a dedicated mart (defined in config/marts.yaml: serve_agents, win_agents)
#   - a service principal assigned only to that mart's reader group, so it can
#     read only the approved data for that product, enforced by Unity Catalog
#   - a dedicated Small serverless SQL warehouse for compute + cost isolation
#   - CAN_USE (USAGE) on that warehouse
# OAuth M2M credentials for each SP are generated manually and stored in
# Secrets Manager (out of band).

locals {
  # Each product maps to its mart name (config/marts.yaml) and resource names.
  agent_products = {
    serve = {
      mart           = "serve_agents"
      sp_name        = "sp_serve_agent"
      warehouse_name = "wh-serve-agents"
    }
    win = {
      mart           = "win_agents"
      sp_name        = "sp_win_agent"
      warehouse_name = "wh-win-agents"
    }
  }
}

resource "databricks_service_principal" "agent" {
  for_each     = local.agent_products
  provider     = databricks.account
  display_name = each.value.sp_name

  lifecycle {
    prevent_destroy = true
  }
}

# Assign to the workspace so the SP can use workspace-level resources.
resource "databricks_mws_permission_assignment" "agent" {
  for_each     = local.agent_products
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.agent[each.key].id
  permissions  = ["USER"]
}

# Each agent SP is a member only of its own mart reader group, inheriting
# USE_CATALOG (catalog_main) and USE_SCHEMA + SELECT (mart_schemas).
resource "databricks_group_member" "agent_in_mart_readers" {
  for_each  = local.agent_products
  provider  = databricks.account
  group_id  = databricks_group.mart_readers_account[each.value.mart].id
  member_id = databricks_service_principal.agent[each.key].id
}

# Dedicated Small serverless warehouse per agent for compute + cost isolation.
resource "databricks_sql_endpoint" "agent" {
  for_each                  = local.agent_products
  name                      = each.value.warehouse_name
  cluster_size              = "Small"
  enable_serverless_compute = true
  warehouse_type            = "PRO"
  auto_stop_mins            = 10
  max_num_clusters          = 1

  tags {
    custom_tags {
      key   = "product"
      value = each.key
    }
    custom_tags {
      key   = "purpose"
      value = "agent"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# USAGE on the warehouse for the matching agent SP.
resource "databricks_permissions" "agent_warehouse" {
  for_each        = local.agent_products
  sql_endpoint_id = databricks_sql_endpoint.agent[each.key].id

  access_control {
    service_principal_name = databricks_service_principal.agent[each.key].application_id
    permission_level       = "CAN_USE"
  }

  depends_on = [databricks_mws_permission_assignment.agent]
}
