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

# Adopt the existing model_predictions schema instead of recreating it
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
