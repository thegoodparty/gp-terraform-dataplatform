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

  # dbt_cloud_staging service principal gets read access across catalog,
  # write access is scoped to the dbt_staging schema only
  grant {
    principal  = databricks_service_principal.dbt_cloud_staging.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
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

  # data-engineers group gets read access and grant management across entire catalog
  grant {
    principal  = data.databricks_group.data_engineers.display_name
    privileges = ["SELECT", "MANAGE"]
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

  depends_on = [
    databricks_group.mart_readers_account,
    databricks_group.dbt_developers_account
  ]
}

# =============================================================================
# External Location Permissions
# =============================================================================

data "databricks_external_location" "storage" {
  name = "db_s3_external_databricks-s3-ingest-dbca4"
}

resource "databricks_grants" "external_location_storage" {
  external_location = data.databricks_external_location.storage.id

  grant {
    principal  = data.databricks_service_principal.github_action.application_id
    privileges = ["CREATE_MANAGED_STORAGE"]
  }

  grant {
    principal  = data.databricks_group.data_engineers.display_name
    privileges = ["CREATE_EXTERNAL_TABLE", "READ_FILES", "WRITE_FILES"]
  }
}

# People-API loader external location. The loader runs as the airflow SPs
# (prod `airflow`, dev `airflow_dev`), which need WRITE to INSERT OVERWRITE DIRECTORY into the
# bucket. Location + credential are defined in loader_storage.tf.
resource "databricks_grants" "loader_external_location" {
  external_location = databricks_external_location.loader.id

  dynamic "grant" {
    for_each = databricks_service_principal.airflow
    content {
      principal  = grant.value.application_id
      privileges = ["READ_FILES", "WRITE_FILES"]
    }
  }
}

resource "databricks_grants" "catalog_segment_storage" {
  catalog = databricks_catalog.segment_storage.name

  grant {
    principal  = databricks_service_principal.segment_storage.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_SCHEMA", "CREATE_TABLE"]
  }

  grant {
    principal  = data.databricks_service_principal.dbt_cloud.application_id
    privileges = ["EXECUTE", "READ_VOLUME", "SELECT", "USE_CATALOG", "USE_SCHEMA"]
  }

  grant {
    principal  = databricks_service_principal.dbt_cloud_staging.application_id
    privileges = ["EXECUTE", "READ_VOLUME", "SELECT", "USE_CATALOG", "USE_SCHEMA"]
  }

  grant {
    principal  = data.databricks_group.data_engineers.display_name
    privileges = ["EXECUTE", "READ_VOLUME", "SELECT", "USE_CATALOG", "USE_SCHEMA"]
  }
}

# =============================================================================
# System Tables Permissions
# =============================================================================

resource "databricks_grant" "system_catalog_data_engineers" {
  catalog = "system"

  principal  = data.databricks_group.data_engineers.display_name
  privileges = ["USE_CATALOG"]
}

resource "databricks_grant" "system_access_schema_data_engineers" {
  schema = "system.access"

  principal  = data.databricks_group.data_engineers.display_name
  privileges = ["USE_SCHEMA"]
}

resource "databricks_grant" "system_access_audit_data_engineers" {
  table = "system.access.audit"

  principal  = data.databricks_group.data_engineers.display_name
  privileges = ["SELECT"]
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

# MBAN models schema permissions
resource "databricks_grants" "models_mban_schema" {
  schema = databricks_schema.models_mban.id

  # MBAN readers group can create and manage ML models
  grant {
    principal = databricks_group.mart_readers_account["mban2026"].display_name
    privileges = [
      "USE_SCHEMA",
      "SELECT",
      "CREATE_TABLE",
      "MODIFY",
      "CREATE_MODEL",
      "EXECUTE"
    ]
  }
}

# Singular grant won't clobber grants set outside Terraform
resource "databricks_grant" "model_predictions_ml_users" {
  schema = databricks_schema.model_predictions.id

  principal = data.databricks_group.ml_users.display_name
  privileges = [
    "USE_SCHEMA",
    "CREATE_MODEL",
    "CREATE_MODEL_VERSION"
  ]
}

# Singular grant won't clobber grants set outside Terraform.
# dbt-users is the dbt Cloud CI/transform principal group. It needs EXECUTE to
# load the viability MLflow models in the int__civics_viability_scoring waterfall
# (DATA-1938). Granted at the SCHEMA level so all current and future models are
# covered: a per-model EXECUTE grant existed only on viabilitywithopponentdata,
# so CI broke when the other four waterfall models were copied in without it.
resource "databricks_grant" "model_predictions_dbt_users" {
  schema = databricks_schema.model_predictions.id

  principal = data.databricks_group.dbt_users.display_name
  privileges = [
    "USE_SCHEMA",
    "EXECUTE"
  ]
}

# ml-users get everything in sandbox
resource "databricks_grant" "sandbox_ml_users" {
  schema = "${databricks_catalog.main.name}.sandbox"

  principal  = data.databricks_group.ml_users.display_name
  privileges = ["ALL_PRIVILEGES"]
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

  # data users get read-only access
  grant {
    principal = data.databricks_group.data_users.display_name
    privileges = [
      "USE_SCHEMA",
      "SELECT"
    ]
  }

}

# =============================================================================
# people-api Serving Table Permissions
# =============================================================================

# Interim read access for the gp-api application. Its own mart passes the raw L2
# record through, but the app's queries are written against the people-db column
# names, which only the m_people_api__* serving models carry. Scoped to those two
# tables so the rest of the dbt working schema stays closed. Remove once the
# mart serves the same shape.
#
# Singular grants: the dbt schema carries grants set outside Terraform.
resource "databricks_grant" "dbt_schema_gp_api" {
  schema = "${databricks_catalog.main.name}.dbt"

  principal  = databricks_service_principal.gp_api.application_id
  privileges = ["USE_SCHEMA"]
}

resource "databricks_grant" "people_api_serving_gp_api" {
  for_each = toset(["m_people_api__voter", "m_people_api__district"])

  table = "${databricks_catalog.main.name}.dbt.${each.value}"

  principal  = databricks_service_principal.gp_api.application_id
  privileges = ["SELECT"]
}

# =============================================================================
# SQL Warehouse Permissions
# =============================================================================

data "databricks_sql_warehouse" "starter" {
  name = "Serverless Starter Warehouse"
}

resource "databricks_permissions" "sql_warehouse_starter" {
  sql_endpoint_id = data.databricks_sql_warehouse.starter.id

  # Note: admins group has CAN_MANAGE by default (built-in, cannot be modified)

  access_control {
    group_name       = "users"
    permission_level = "CAN_USE"
  }

  access_control {
    service_principal_name = databricks_service_principal.segment_storage.application_id
    permission_level       = "CAN_USE"
  }

  # People-API loader: the unload + dbt-test gate run on this warehouse as the
  # airflow SPs (prod `airflow`, dev `airflow_dev`), so both need CAN_USE.
  dynamic "access_control" {
    for_each = databricks_service_principal.airflow
    content {
      service_principal_name = access_control.value.application_id
      permission_level       = "CAN_USE"
    }
  }

  # Analytics governance loop reads the two dbt tables from this warehouse.
  access_control {
    service_principal_name = databricks_service_principal.product_analytics.application_id
    permission_level       = "CAN_USE"
  }

  # Edge to the SPs' workspace assignments so the workspace-scoped grant doesn't run before
  # they're workspace members (matches sigma_pov/agent below).
  depends_on = [
    databricks_mws_permission_assignment.airflow,
    databricks_mws_permission_assignment.product_analytics,
  ]
}

# CAN_USE on the Sigma BI warehouse (databricks_sql_endpoint.sigma in warehouses.tf).
resource "databricks_permissions" "sql_warehouse_sigma_pov" {
  sql_endpoint_id = databricks_sql_endpoint.sigma.id

  access_control {
    service_principal_name = databricks_service_principal.sigma.application_id
    permission_level       = "CAN_USE"
  }

  depends_on = [databricks_mws_permission_assignment.sigma]
}

# CAN_USE on each product agent warehouse for its matching SP.
resource "databricks_permissions" "agent_warehouse" {
  for_each        = local.agent_products
  sql_endpoint_id = databricks_sql_endpoint.agent[each.key].id

  access_control {
    service_principal_name = databricks_service_principal.agent[each.key].application_id
    permission_level       = "CAN_USE"
  }

  depends_on = [databricks_mws_permission_assignment.agent]
}

# CAN_USE on the gp-api application warehouse (databricks_sql_endpoint.gp_api).
resource "databricks_permissions" "sql_warehouse_gp_api" {
  sql_endpoint_id = databricks_sql_endpoint.gp_api.id

  access_control {
    service_principal_name = databricks_service_principal.gp_api.application_id
    permission_level       = "CAN_USE"
  }

  depends_on = [databricks_mws_permission_assignment.gp_api]
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

  access_control {
    service_principal_name = databricks_service_principal.dbt_cloud_staging.application_id
    permission_level       = "CAN_RESTART"
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

  access_control {
    service_principal_name = databricks_service_principal.dbt_cloud_staging.application_id
    permission_level       = "CAN_USE"
  }

  access_control {
    service_principal_name = databricks_service_principal.sigma.application_id
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
# Secret Scope Permissions
# =============================================================================

resource "databricks_secret_acl" "dbt_cloud_staging_secrets_dev" {
  principal  = databricks_service_principal.dbt_cloud_staging.application_id
  permission = "READ"
  scope      = "dbt-secrets-dev"
}

# =============================================================================
# File-level Permissions
# =============================================================================

resource "databricks_sql_permissions" "select_any_file" {
  any_file = true

  privilege_assignments {
    principal  = data.databricks_group.dbt_users.display_name
    privileges = ["SELECT"]
  }

  privilege_assignments {
    principal  = data.databricks_service_principal.dbt_cloud.application_id
    privileges = ["SELECT"]
  }

  privilege_assignments {
    principal  = databricks_service_principal.dbt_cloud_staging.application_id
    privileges = ["SELECT"]
  }
}

# =============================================================================
# dbt Cloud Staging Schema Permissions
# =============================================================================

resource "databricks_grants" "dbt_staging_schema" {
  schema = databricks_schema.dbt_staging.id

  grant {
    principal = databricks_service_principal.dbt_cloud_staging.application_id
    privileges = [
      "USE_SCHEMA",
      "CREATE_TABLE",
      "MODIFY",
      "CREATE_FUNCTION"
    ]
  }

  grant {
    principal = data.databricks_group.data_engineers.display_name
    privileges = [
      "USE_SCHEMA",
      "EXECUTE"
    ]
  }
}
