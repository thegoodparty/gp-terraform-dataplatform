# =============================================================================
# Unity Catalog Managed Volumes
# =============================================================================

# Existing prod volume — imported into state
resource "databricks_volume" "dbt_object_storage" {
  name         = "object_storage"
  catalog_name = databricks_catalog.main.name
  schema_name  = "dbt"
  volume_type  = "MANAGED"
  owner        = data.databricks_service_principal.dbt_cloud.application_id

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

# Staging volume for dbt Cloud staging environment
resource "databricks_volume" "dbt_staging_object_storage" {
  name         = "object_storage"
  catalog_name = databricks_catalog.main.name
  schema_name  = databricks_schema.dbt_staging.name
  volume_type  = "MANAGED"
  comment      = "Object storage volume for dbt Cloud staging environment"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.dbt_staging_schema]
}

# CSV preview output for the reverse-ETL app's csv destination (a preview run, never
# logged as sent). Schema-level USE_SCHEMA/SELECT do not cover volume file access, so
# this needs its own grants below.
resource "databricks_volume" "reverse_etl_csv_preview" {
  name         = "csv_preview"
  catalog_name = databricks_catalog.main.name
  schema_name  = databricks_schema.reverse_etl.name
  volume_type  = "MANAGED"
  comment      = "Reverse-ETL CSV preview output. Preview and sandbox runs only; never a substitute for sent_log."

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Volume Grants
# =============================================================================

# Grants on prod dbt.object_storage volume (no existing direct grants to import)
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

# Grants on reverse_etl.csv_preview volume: the job reads and writes previews, the
# data team can inspect what would have gone out.
resource "databricks_grants" "reverse_etl_csv_preview_volume" {
  volume = databricks_volume.reverse_etl_csv_preview.id

  grant {
    principal  = databricks_service_principal.airflow["airflow"].application_id
    privileges = ["READ_VOLUME", "WRITE_VOLUME"]
  }

  grant {
    principal  = databricks_group.dbt_developers_account.display_name
    privileges = ["READ_VOLUME"]
  }
}
