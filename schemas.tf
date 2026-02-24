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

# dbt Cloud staging source schema for L2 and other source data loads
resource "databricks_schema" "dbt_staging_source" {
  catalog_name = databricks_catalog.main.name
  name         = "dbt_staging_source"
  comment      = "Source schema for dbt Cloud staging environment"

  properties = {
    managed_by = "terraform"
    purpose    = "dbt_staging_source"
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
