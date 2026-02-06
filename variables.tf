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

# Astro environment configuration type
variable "astro_env_dev" {
  description = "Dev Astro deployment configuration (optional)"
  type = object({
    name                    = string
    description             = string
    type                    = string # STANDARD, DEDICATED
    executor                = string # CELERY, KUBERNETES
    is_cicd_enforced        = bool
    is_dag_deploy_enabled   = bool
    is_development_mode     = bool
    is_high_availability    = bool
    default_task_pod_cpu    = string
    default_task_pod_memory = string
    resource_quota_cpu      = string
    resource_quota_memory   = string
    scheduler_size          = string # SMALL, MEDIUM, LARGE
    hibernation_schedules = optional(list(object({
      hibernate_at_cron = string
      wake_at_cron      = string
      description       = string
      is_enabled        = bool
    })), [])
  })
  default = null
}

variable "astro_env_prod" {
  description = "Prod Astro deployment configuration (optional)"
  type = object({
    name                    = string
    description             = string
    type                    = string # STANDARD, DEDICATED
    executor                = string # CELERY, KUBERNETES
    is_cicd_enforced        = bool
    is_dag_deploy_enabled   = bool
    is_development_mode     = bool
    is_high_availability    = bool
    default_task_pod_cpu    = string
    default_task_pod_memory = string
    resource_quota_cpu      = string
    resource_quota_memory   = string
    scheduler_size          = string # SMALL, MEDIUM, LARGE
    hibernation_schedules = optional(list(object({
      hibernate_at_cron = string
      wake_at_cron      = string
      description       = string
      is_enabled        = bool
    })), [])
  })
  default = null
}
