# Zapier exports schema for data exported to Zapier integrations
resource "databricks_schema" "exports_zapier" {
  catalog_name = databricks_catalog.main.name
  name         = "exports_zapier"
  comment      = "Schema for data exported to Zapier integrations"

  properties = {
    managed_by = "terraform"
    purpose    = "exports"
  }

  lifecycle {
    prevent_destroy = true
  }

  # Wait for catalog grants (including CREATE_SCHEMA for github-action SP)
  depends_on = [databricks_grants.catalog_main]
}

# dbt Cloud staging schema for the staging deployment environment
resource "databricks_schema" "dbt_staging" {
  catalog_name = databricks_catalog.main.name
  name         = "dbt_staging"
  comment      = "Schema for dbt Cloud staging environment"

  properties = {
    managed_by = "terraform"
    purpose    = "dbt_staging"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# MBAN models schema for ML model storage and ad hoc objects
resource "databricks_schema" "models_mban" {
  catalog_name = databricks_catalog.main.name
  name         = "models_mban"
  comment      = "Schema for MBAN team ML models and predictions"

  properties = {
    managed_by = "terraform"
    purpose    = "models"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# exising model_predictions schema, now under terraform management
import {
  to = databricks_schema.model_predictions
  id = "goodparty_data_catalog.model_predictions"
}

resource "databricks_schema" "model_predictions" {
  catalog_name = databricks_catalog.main.name
  name         = "model_predictions"
  comment      = "Schema for ML model registration and prediction outputs"

  properties = {
    managed_by = "terraform"
    purpose    = "models"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# Standalone on purpose (not a config/marts.yaml mart): a send log, not a queryable mart.
resource "databricks_schema" "reverse_etl" {
  catalog_name = databricks_catalog.main.name
  name         = "reverse_etl"
  comment      = "Reverse-ETL send-log tables, created and owned by the reverse-ETL job (one per flow). Not a mart and not in any shared-marts rollup; read access rides the catalog-level grants."

  properties = {
    managed_by = "terraform"
    purpose    = "reverse_etl"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# Dev counterpart of the unmanaged er_source schema. One catalog serves both
# environments and matcha's dated table names carry only the run date, so
# sharing er_source would have a dev run and a prod run fight over the same
# vintage, and a dev swap rename what the civics marts read.
resource "databricks_schema" "er_source_dev" {
  catalog_name = databricks_catalog.main.name
  name         = "er_source_dev"
  comment      = "Entity-resolution outputs from the dev Airflow deployment. Prod writes the unmanaged er_source schema."

  properties = {
    managed_by = "terraform"
    purpose    = "entity_resolution_dev"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# Dynamic mart schemas from YAML configuration
resource "databricks_schema" "marts" {
  for_each = local.marts_map

  catalog_name = databricks_catalog.main.name
  name         = "mart_${each.key}"
  comment      = each.value.description

  properties = {
    managed_by = "terraform"
    purpose    = "mart"
  }

  lifecycle {
    prevent_destroy = true
  }
}
