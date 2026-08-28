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
# People-API loader storage
# Dedicated S3 bucket the loader's `unload` step writes to (Databricks) and the
# `copy` step reads from (Aurora), plus the UC external location + storage
# credential + dedicated service principal that govern Databricks access.
# =============================================================================

variable "aws_region" {
  description = "AWS region for the loader S3 bucket + IAM"
  type        = string
  default     = "us-west-2"
}

# Loader resource names (bucket, IAM roles, UC credential/location, SP) are fixed
# single-environment constants, defined as locals in loader_storage.tf rather than
# variables, matching the repo's convention of literal resource names.

variable "loader_export_lifecycle_days" {
  description = "Expire voter_export_*/ objects after this many days (per-run exports are disposable post-cutover)."
  type        = number
  default     = 30
}

variable "loader_db_cluster_prefix" {
  description = <<-EOT
    Name prefix of the Aurora clusters the loader provisions (loader config.py names them
    gp-people-db-<run_date>). Used to scope the rds-s3-import role's trust to aws:SourceArn,
    so only the loader's own clusters can assume it. Must match the loader's new_cluster_id.
  EOT
  type        = string
  default     = "gp-people-db"
}

# =============================================================================
# gp-api always-on serving cluster
# =============================================================================
# Both knobs exist because this cluster is an experiment. Sizing it is meant to
# be a one-line change so we can retest without editing the resource.

variable "gp_api_cluster_node_type" {
  description = <<-EOT
    Instance type for the single-node gp-api serving cluster. The node runs
    around the clock, so this is the cost lever: DBUs scale with instance size
    and are billed on top of the EC2 hour, and DBUs are the larger share.

    The default is a modern 4-core instance because compilation, which is driver
    CPU work, dominates median latency more than execution does. Prefer a family
    with local NVMe (m6id, m5d, r6id, i3) for the disk cache; enable_elastic_disk
    is off in clusters.tf on that assumption.

    Measured rates on this account: m5d.large 0.305 DBU/hr, i3.xlarge 1.0. The
    default works out near $434/month all in. Sizing up to 8 cores roughly
    doubles that and still lands well under what the serverless warehouse costs
    today, so there is room to grow if concurrency turns out to be the limit.
  EOT
  type        = string
  default     = "m6id.xlarge"
}

variable "gp_api_cluster_photon" {
  description = <<-EOT
    Whether the gp-api serving cluster runs Photon. Photon roughly doubles DBU
    consumption, which cancels most of the saving this cluster is meant to test,
    so it starts off. The query history supports that default: execution is a
    small share of total latency and nothing spills.

    Turn it on if warm execution, rather than cold start or queueing, turns out
    to be what users feel.
  EOT
  type        = bool
  default     = false
}

variable "loader_rds_admin_external_ids" {
  description = <<-EOT
    sts:ExternalId the Astro workload-identity role must present when assuming
    gp-people-rds-admin-<env> (confused-deputy guard). Map keyed by environment
    ("dev"/"prod"). Not a credential (a fixed nonce), so it is a repository
    Variable, not a Secret: CI assembles it in terraform.tfvars from
    ASTRO_ASSUME_ROLE_EXTERNAL_ID_DEV/_PROD (same values as omni). Must match what
    each Astro deployment sends, or the role trust policy import shows a diff.
  EOT
  type        = map(string)
}
