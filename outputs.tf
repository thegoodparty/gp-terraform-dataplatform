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
# People-API Loader Outputs (DATA-1905)
# =============================================================================

output "loader_bucket" {
  description = "Name of the people-api loader S3 bucket"
  value       = aws_s3_bucket.loader.bucket
}

output "rds_s3_import_role_arn" {
  description = "ARN of the rds-s3-import role; set as the loader's LOADER_S3_IMPORT_ROLE_ARN"
  value       = aws_iam_role.rds_s3_import.arn
}

# =============================================================================
# Product Agent Outputs
# =============================================================================

output "agent_service_principals" {
  description = "Application IDs of the product agent service principals"
  value = {
    for key, sp in databricks_service_principal.agent :
    key => sp.application_id
  }
}

output "agent_warehouses" {
  description = "Names and IDs of the product agent SQL warehouses"
  value = {
    for key, wh in databricks_sql_endpoint.agent :
    key => {
      name = wh.name
      id   = wh.id
    }
  }
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

