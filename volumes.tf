# =============================================================================
# Unity Catalog Managed Volumes
# =============================================================================

# Existing prod volume — import with:
#   terraform import databricks_volume.dbt_object_storage goodparty_data_catalog.dbt.object_storage
resource "databricks_volume" "dbt_object_storage" {
  name             = "object_storage"
  catalog_name     = databricks_catalog.main.name
  schema_name      = "dbt"
  volume_type      = "MANAGED"
  comment          = "Object storage volume for dbt prod environment"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

# Staging volume for dbt Cloud staging environment
resource "databricks_volume" "dbt_staging_object_storage" {
  name             = "object_storage"
  catalog_name     = databricks_catalog.main.name
  schema_name      = databricks_schema.dbt_staging.name
  volume_type      = "MANAGED"
  comment          = "Object storage volume for dbt Cloud staging environment"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.dbt_staging_schema]
}

# =============================================================================
# Volume Grants
# =============================================================================

# Grants on prod dbt.object_storage volume
# Import with:
#   terraform import databricks_grants.dbt_object_storage_volume goodparty_data_catalog.dbt.object_storage
resource "databricks_grants" "dbt_object_storage_volume" {
  volume = databricks_volume.dbt_object_storage.id

  grant {
    principal  = data.databricks_service_principal.dbt_cloud.application_id
    privileges = ["READ_VOLUME", "WRITE_VOLUME"]
  }
}

# Grants on staging dbt_staging.object_storage volume
resource "databricks_grants" "dbt_staging_object_storage_volume" {
  volume = databricks_volume.dbt_staging_object_storage.id

  grant {
    principal  = databricks_service_principal.dbt_cloud_staging.application_id
    privileges = ["READ_VOLUME", "WRITE_VOLUME"]
  }
}
