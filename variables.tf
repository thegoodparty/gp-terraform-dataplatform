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

# Databricks CLI profile for workspace-level operations (local dev)
variable "databricks_workspace_profile" {
  description = "Databricks CLI profile name for workspace authentication (leave null for CI)"
  type        = string
  default     = null
}

# Databricks workspace host URL (for CI, or leave null to use profile)
variable "databricks_workspace_host" {
  description = "Databricks workspace URL (e.g., https://xxx.cloud.databricks.com)"
  type        = string
  default     = null
}

# Databricks CLI profile for account-level operations (local dev)
variable "databricks_account_profile" {
  description = "Databricks CLI profile name for account-level authentication (leave null for CI)"
  type        = string
  default     = null
}

# S3 bucket for Unity Catalog managed storage
variable "catalog_storage_bucket" {
  description = "S3 bucket URL for Unity Catalog managed storage (e.g., s3://my-bucket)"
  type        = string

  validation {
    condition     = can(regex("^s3://[^/]+[^/]$", var.catalog_storage_bucket))
    error_message = "Must be an S3 bucket URL without trailing slash (e.g., s3://my-bucket)"
  }
}

# =============================================================================
# Astronomer (Astro) Variables
# =============================================================================
# Note: Databricks service principal auth uses environment variables in CI:
#   DATABRICKS_CLIENT_ID and DATABRICKS_CLIENT_SECRET

variable "astro_organization_id" {
  description = "Astronomer organization ID"
  type        = string
}

variable "astro_cloud_provider" {
  description = "Cloud provider for Astro deployments"
  type        = string
  default     = "AWS"
}

variable "astro_region" {
  description = "Region for Astro deployments"
  type        = string
  default     = "us-west-2"
}

variable "astro_contact_emails" {
  description = "Contact emails for Astro deployment alerts"
  type        = list(string)
}

# Note: Astro environment configs (dev/prod) are defined in locals.tf
# Both Airflow environments live in our single infrastructure

# =============================================================================
# People-API loader storage (DATA-1905)
# Dedicated S3 bucket the loader's `unload` step writes to (Databricks) and the
# `copy` step reads from (Aurora), plus the UC external location + storage
# credential + dedicated service principal that govern Databricks access.
# =============================================================================

variable "aws_region" {
  description = "AWS region for the loader S3 bucket + IAM"
  type        = string
  default     = "us-west-2"
}

variable "loader_s3_bucket" {
  description = <<-EOT
    Name of the dedicated loader S3 bucket to create. Must match the loader's
    LOADER_S3_BUCKET env var. Region-suffixed to keep the name globally unique.
  EOT
  type        = string
  default     = "gp-people-loader-us-west-2"
}

variable "loader_export_lifecycle_days" {
  description = "Expire voter_export_*/ objects after this many days (per-run exports are disposable post-cutover)."
  type        = number
  default     = 30
}

variable "loader_uc_role_name" {
  description = "Name of the IAM role Databricks Unity Catalog assumes to read/write the loader bucket."
  type        = string
  default     = "gp-people-loader-uc-access"
}

variable "loader_storage_credential_name" {
  description = "Databricks UC storage credential name for the loader bucket."
  type        = string
  default     = "people-loader-s3"
}

variable "loader_external_location_name" {
  description = "Databricks UC external location name for the loader bucket."
  type        = string
  default     = "people-loader"
}

variable "loader_service_principal_name" {
  description = "Display name of the dedicated loader service principal (the unload warehouse runs as this)."
  type        = string
  default     = "people-api-loader"
}

variable "rds_s3_import_role_name" {
  description = <<-EOT
    Name of the rds-s3-import IAM role created here for Aurora's
    aws_s3.table_import_from_s3 (the loader's `copy` step). Keep the rds-s3-import-*
    prefix so the worker role's iam:PassRole grant (DATA-1856) covers it, and set the
    loader's LOADER_S3_IMPORT_ROLE_ARN to this role's ARN (see the rds_s3_import_role_arn output).
  EOT
  type        = string
  default     = "rds-s3-import-people-loader"
}
