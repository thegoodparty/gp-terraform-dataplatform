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

  # dbt-developers get catalog access
  grant {
    principal  = databricks_group.dbt_developers_account.display_name
    privileges = ["USE_CATALOG"]
  }

  # dbt_cloud service principal gets full access across entire catalog
  grant {
    principal  = data.databricks_service_principal.dbt_cloud.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE"]
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

  # ai-infra service principal gets schema access and read access across entire catalog
  grant {
    principal  = data.databricks_service_principal.ai_infra.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
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

  depends_on = [
    databricks_group.mart_readers_account,
    databricks_group.dbt_developers_account
  ]
}
