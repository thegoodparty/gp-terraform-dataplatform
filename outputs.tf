output "catalog_name" {
  description = "Name of the main data catalog"
  value       = databricks_catalog.main.name
}

output "loaded_marts" {
  description = "Marts loaded from YAML configuration"
  value       = [for mart in local.marts : mart.name]
}

output "mart_schemas" {
  description = "All mart schema full names"
  value = {
    for name, schema in databricks_schema.marts :
    name => "${databricks_catalog.main.name}.${schema.name}"
  }
}

output "mart_reader_groups" {
  description = "Display names of mart reader account-level groups"
  value = {
    for name, group in databricks_group.mart_readers_account :
    name => group.display_name
  }
}

output "dbt_developers_group" {
  description = "Display name of dbt-developers account-level group"
  value       = databricks_group.dbt_developers_account.display_name
}

# =============================================================================
# Astronomer (Astro) Outputs
# =============================================================================

output "astro_workspace_id" {
  description = "Astro workspace ID"
  value       = astro_workspace.data_engineering.id
}

output "astro_workspace_name" {
  description = "Astro workspace name"
  value       = astro_workspace.data_engineering.name
}

output "astro_deployments" {
  description = "Astro deployment details"
  value = {
    for name, deployment in astro_deployment.environments :
    name => {
      id            = deployment.id
      name          = deployment.name
      webserver_url = deployment.webserver_url
      workspace_id  = deployment.workspace_id
    }
  }
}

