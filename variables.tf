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
# Note: in CI, Databricks auth is GitHub OIDC federation as the github-action SP
# (DATABRICKS_CLIENT_ID + DATABRICKS_AUTH_TYPE=github-oidc); no client secret.

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
# gp-api Postgres mirror (gp_api_mirror.tf)
# =============================================================================

variable "gp_api_mirror_connected_envs" {
  description = <<-EOT
    Mirror environments ("dev", "prod") whose Unity Catalog connection and
    Postgres replication slot already exist. Only these get the connection
    grant, the gateway, the ingestion pipeline and the loop job. The gateway
    starts as soon as it is created, so add an env only after its slot exists.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for env in var.gp_api_mirror_connected_envs : contains(["dev", "prod"], env)])
    error_message = "Each entry must be \"dev\" or \"prod\"."
  }
}

variable "gp_api_mirror_notification_emails" {
  description = "Recipients of the mirror's gateway, pipeline and job failure emails. CI fills it from ASTRO_CONTACT_EMAILS."
  type        = list(string)
}

# =============================================================================
# gp-api Postgres federation (gp_api_federation.tf)
# =============================================================================

variable "gp_api_federation_envs" {
  description = <<-EOT
    Federation environments ("dev", "prod") mapped to the VPC endpoint service
    name omni's Pulumi stack outputs as databricksEndpointServiceName. Only
    these get the NCC private endpoint rule, the foreign catalog and its
    grants. Add an env only after its endpoint service and Unity Catalog
    connection exist.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for env in keys(var.gp_api_federation_envs) : contains(["dev", "prod"], env)])
    error_message = "Each key must be \"dev\" or \"prod\"."
  }
}

# =============================================================================
# AWS (IAM roles the Airflow DAGs assume, S3 lifecycle rules)
# =============================================================================

variable "aws_region" {
  description = "AWS region for the platform's IAM roles and S3 configuration"
  type        = string
  default     = "us-west-2"
}

variable "astro_workload_external_ids" {
  description = <<-EOT
    sts:ExternalId the Astro workload-identity role must present when assuming
    any role Airflow uses (gp-l2-voter-files-<env>, etc.)
    (confused-deputy guard). Map keyed by environment
    ("dev"/"prod"). Not a credential (a fixed nonce), so it is a repository
    Variable, not a Secret: CI assembles it in terraform.tfvars from
    ASTRO_ASSUME_ROLE_EXTERNAL_ID_DEV/_PROD (same values as omni). Must match what
    each Astro deployment sends, or the role trust policy import shows a diff.
  EOT
  type        = map(string)
}
