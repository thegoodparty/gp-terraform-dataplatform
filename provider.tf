# Databricks workspace-level provider (for catalogs, schemas, workspace resources)
provider "databricks" {
  profile = var.databricks_workspace_profile
}

# Databricks account-level provider (for account groups, service principals)
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
  profile    = var.databricks_account_profile
}
