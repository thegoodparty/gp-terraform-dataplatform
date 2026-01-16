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
