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
  comment      = "Reverse-ETL send log: records every payload delivered to a destination. Access is scoped to the sales reverse-ETL readers group rather than rolled into shared_marts, matching that mart's posture."

  properties = {
    managed_by = "terraform"
    purpose    = "reverse_etl"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# Terraform owns this DDL exclusively: the job only appends, so a missing table fails
# the run instead of silently re-sending everyone. Four columns is deliberate.
resource "databricks_sql_table" "sent_log" {
  name               = "sent_log"
  catalog_name       = databricks_catalog.main.name
  schema_name        = databricks_schema.reverse_etl.name
  table_type         = "MANAGED"
  data_source_format = "DELTA"
  warehouse_id       = data.databricks_sql_warehouse.starter.id
  cluster_keys       = ["flow_id", "tracking_key"]
  comment            = "Every reverse-ETL delivery, one row per send. Append-only for the job; deletes are a break-glass admin action."

  column {
    name     = "flow_id"
    type     = "STRING"
    nullable = false
  }

  column {
    name     = "tracking_key"
    type     = "STRING"
    nullable = false
  }

  column {
    name     = "payload"
    type     = "STRING"
    nullable = false
  }

  column {
    name     = "sent_at"
    type     = "TIMESTAMP"
    nullable = false
  }

  lifecycle {
    prevent_destroy = true
  }
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
