# Catalog-level permissions - grant USE_CATALOG to all account-level groups
resource "databricks_grants" "catalog_main" {
  catalog = databricks_catalog.main.name

  # Mart reader groups get catalog access
  dynamic "grant" {
    for_each = databricks_group.mart_readers_account
    content {
      principal  = grant.value.display_name
      privileges = ["USE_CATALOG"]
    }
  }

  # dbt-developers get catalog access and can create schemas
  grant {
    principal  = databricks_group.dbt_developers_account.display_name
    privileges = ["USE_CATALOG", "CREATE_SCHEMA"]
  }

  # dbt_cloud service principal gets full access across entire catalog
  grant {
    principal  = data.databricks_service_principal.dbt_cloud.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE", "CREATE_SCHEMA"]
  }

  # airbyte service principal gets catalog access
  grant {
    principal  = data.databricks_service_principal.airbyte.application_id
    privileges = ["USE_CATALOG"]
  }

  # Existing groups get catalog access
  grant {
    principal  = data.databricks_group.account_users.display_name
    privileges = ["USE_CATALOG"]
  }

  grant {
    principal  = data.databricks_group.admin_group.display_name
    privileges = ["USE_CATALOG"]
  }

  grant {
    principal  = data.databricks_group.data_users.display_name
    privileges = ["USE_CATALOG", "USE_SCHEMA"]
  }

  # ai-owners group gets schema access across entire catalog
  grant {
    principal  = data.databricks_group.ai_owners.display_name
    privileges = ["USE_SCHEMA"]
  }

  # data-engineers group gets read access across entire catalog
  grant {
    principal  = data.databricks_group.data_engineers.display_name
    privileges = ["SELECT"]
  }

  # dbt-users get catalog access and can create schemas
  grant {
    principal  = data.databricks_group.dbt_users.display_name
    privileges = ["USE_CATALOG", "CREATE_SCHEMA"]
  }

  # ai-infra service principal gets schema access and read access across entire catalog
  grant {
    principal  = data.databricks_service_principal.ai_infra.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }

  # zapier service principal gets catalog access for zapier_exports schema
  grant {
    principal  = data.databricks_service_principal.zapier.application_id
    privileges = ["USE_CATALOG"]
  }

  # github-action service principal for CI/CD
  grant {
    principal  = data.databricks_service_principal.github_action.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_SCHEMA"]
  }

  # airflow service principals can create and own their own schemas
  dynamic "grant" {
    for_each = databricks_service_principal.airflow
    content {
      principal  = grant.value.application_id
      privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_SCHEMA"]
    }
  }

  # Segment SP - creates and owns its own schemas for storage destination
  grant {
    principal  = databricks_service_principal.segment.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_SCHEMA", "CREATE_TABLE"]
  }

  depends_on = [
    databricks_group.mart_readers_account,
    databricks_group.dbt_developers_account
  ]
}

# Mart schema permissions - each reader group and dbt-developers get read access
resource "databricks_grants" "mart_schemas" {
  for_each = local.marts_map

  schema = databricks_schema.marts[each.key].id

  grant {
    principal = databricks_group.mart_readers_account[each.key].display_name
    privileges = [
      "USE_SCHEMA",
      "SELECT"
    ]
  }

  grant {
    principal = databricks_group.dbt_developers_account.display_name
    privileges = [
      "USE_SCHEMA",
      "SELECT"
    ]
  }

  # dbt_cloud service principal gets write access to create and manage tables/views
  # CREATE_TABLE covers both tables and views in privilege model 1.0
  # SELECT is granted at catalog level for read access across all schemas
  grant {
    principal = data.databricks_service_principal.dbt_cloud.application_id
    privileges = [
      "USE_SCHEMA",
      "CREATE_TABLE",
      "MODIFY"
    ]
  }

  # github-action service principal for CI/CD (read-only for terraform plan)
  grant {
    principal = data.databricks_service_principal.github_action.application_id
    privileges = [
      "USE_SCHEMA",
      "SELECT"
    ]
  }

  depends_on = [
    databricks_group.mart_readers_account,
    databricks_group.dbt_developers_account
  ]
}

# Zapier exports schema permissions
resource "databricks_grants" "exports_zapier_schema" {
  schema = databricks_schema.exports_zapier.id

  # zapier service principal gets read-only access
  grant {
    principal = data.databricks_service_principal.zapier.application_id
    privileges = [
      "USE_SCHEMA",
      "SELECT"
    ]
  }

  # dbt-users get create/modify access
  grant {
    principal = data.databricks_group.dbt_users.display_name
    privileges = [
      "USE_SCHEMA",
      "SELECT",
      "CREATE_TABLE",
      "MODIFY"
    ]
  }

  # dbt_cloud service principal also gets write access for automation
  grant {
    principal = data.databricks_service_principal.dbt_cloud.application_id
    privileges = [
      "USE_SCHEMA",
      "CREATE_TABLE",
      "MODIFY"
    ]
  }

}

# =============================================================================
# SQL Warehouse Permissions
# =============================================================================

data "databricks_sql_warehouse" "starter" {
  name = "Serverless Starter Warehouse"
}

resource "databricks_permissions" "sql_warehouse_starter" {
  sql_endpoint_id = data.databricks_sql_warehouse.starter.id

  access_control {
    service_principal_name = databricks_service_principal.segment.application_id
    permission_level       = "CAN_USE"
  }
}

# =============================================================================
# Compute Cluster Permissions
# =============================================================================
# Grant permissions on the shared compute cluster (classic-cluster)

data "databricks_cluster" "classic" {
  cluster_name = "classic-cluster"
}

resource "databricks_permissions" "cluster_classic" {
  cluster_id = data.databricks_cluster.classic.id

  # Note: admins group has CAN_MANAGE by default (built-in, cannot be modified)

  access_control {
    group_name       = data.databricks_group.dbt_users.display_name
    permission_level = "CAN_RESTART"
  }

  access_control {
    service_principal_name = data.databricks_service_principal.airbyte.application_id
    permission_level       = "CAN_RESTART"
  }

  # Airflow service principals
  dynamic "access_control" {
    for_each = databricks_service_principal.airflow
    content {
      service_principal_name = access_control.value.application_id
      permission_level       = "CAN_RESTART"
    }
  }
}

# =============================================================================
# Token (PAT) Permissions
# =============================================================================
# Manage who can create and use Personal Access Tokens

resource "databricks_permissions" "token_usage" {
  authorization = "tokens"

  # Note: admins group has CAN_MANAGE by default (built-in, cannot be modified)

  # Service principals that need token access
  access_control {
    service_principal_name = data.databricks_service_principal.ai_infra.application_id
    permission_level       = "CAN_USE"
  }

  access_control {
    service_principal_name = data.databricks_service_principal.looker_studio.application_id
    permission_level       = "CAN_USE"
  }

  # Groups that can create/use tokens
  access_control {
    group_name       = data.databricks_group.token_users.display_name
    permission_level = "CAN_USE"
  }

  access_control {
    group_name       = data.databricks_group.dbt_users.display_name
    permission_level = "CAN_USE"
  }

}

# =============================================================================
# Table-level Permissions for Airflow expired voter deletions (DATA-1534)
# =============================================================================

locals {
  airflow_modify_tables = toset([
    "int__l2_nationwide_uniform",
    "m_people_api__voter",
  ])
}

resource "databricks_grants" "airflow_voter_tables" {
  for_each = local.airflow_modify_tables
  table    = "${databricks_catalog.main.name}.dbt.${each.value}"

  dynamic "grant" {
    for_each = databricks_service_principal.airflow
    content {
      principal  = grant.value.application_id
      privileges = ["MODIFY"]
    }
  }
}
