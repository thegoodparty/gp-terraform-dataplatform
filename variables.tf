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

# =============================================================================
# Astronomer (Astro) Variables
# =============================================================================

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
  default     = ["hugh@goodparty.org"]
}

variable "astro_environments" {
  description = "Map of Astro deployment environments to create"
  type = map(object({
    name                    = string
    description             = string
    type                    = string # STANDARD, DEDICATED
    executor                = string # CELERY, KUBERNETES, ASTRO
    is_cicd_enforced        = bool
    is_dag_deploy_enabled   = bool
    is_development_mode     = bool
    is_high_availability    = bool
    default_task_pod_cpu    = string
    default_task_pod_memory = string
    resource_quota_cpu      = string
    resource_quota_memory   = string
    scheduler_size          = string # SMALL, MEDIUM, LARGE
    worker_queues = list(object({
      name               = string
      is_default         = bool
      astro_machine      = string # A5, A10, A20, A40, A60, A120, A160
      max_worker_count   = number
      min_worker_count   = number
      worker_concurrency = number
    }))
    hibernation_schedules = optional(list(object({
      hibernate_at_cron = string
      wake_at_cron      = string
      description       = string
      is_enabled        = bool
    })), [])
  }))
  # Default: only dev deployment
  # Prod is created via GitHub Actions on merge to main
  default = {
    dev = {
      name                    = "astro-dev"
      description             = "Development Airflow environment"
      type                    = "STANDARD"
      executor                = "KUBERNETES"
      is_cicd_enforced        = false
      is_dag_deploy_enabled   = true
      is_development_mode     = true
      is_high_availability    = false
      default_task_pod_cpu    = "0.25"
      default_task_pod_memory = "0.5Gi"
      resource_quota_cpu      = "10"
      resource_quota_memory   = "20Gi"
      scheduler_size          = "SMALL"
      worker_queues           = []
      hibernation_schedules = [
        {
          hibernate_at_cron = "0 1 * * 2,3,4,5,6"
          wake_at_cron      = "0 14 * * 1,2,3,4,5"
          description       = "Hibernate overnight, wake on weekday afternoons UTC"
          is_enabled        = true
        }
      ]
    }
  }
}
