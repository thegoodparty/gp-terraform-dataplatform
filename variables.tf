# Databricks Account ID (required for account-level operations)
variable "databricks_account_id" {
  description = "Databricks account ID (UUID format)"
  type        = string
  sensitive   = true
}

# Databricks workspace ID for account-level operations
variable "workspace_id" {
  description = "Databricks workspace ID for account-level operations"
  type        = string
}

# Databricks CLI profile for workspace-level operations
variable "databricks_workspace_profile" {
  description = "Databricks CLI profile name for workspace authentication"
  type        = string
  default     = "DEFAULT"
}

# Databricks CLI profile for account-level operations
variable "databricks_account_profile" {
  description = "Databricks CLI profile name for account-level authentication"
  type        = string
  default     = "ACCOUNT"
}
