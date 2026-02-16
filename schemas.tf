# Schema for Airflow-managed source data (e.g. expired voter records)
resource "databricks_schema" "airflow_source" {
  catalog_name = databricks_catalog.main.name
  name         = "airflow_source"
  comment      = "Schema for Airflow-managed source data"

  properties = {
    managed_by = "terraform"
    purpose    = "source"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

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
