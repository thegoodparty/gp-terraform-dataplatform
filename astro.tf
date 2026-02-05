# =============================================================================
# Astronomer (Astro) Resources
# =============================================================================
# Manages Astro workspace, deployments, and related resources for Airflow

# -----------------------------------------------------------------------------
# Workspace
# -----------------------------------------------------------------------------

resource "astro_workspace" "data_engineering" {
  name                  = "Data Engineering"
  description           = "Data Engineering workspace for Airflow deployments"
  cicd_enforced_default = false # Requires higher Astro plan tier

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Deployments
# -----------------------------------------------------------------------------

resource "astro_deployment" "environments" {
  for_each = local.astro_environments

  name                    = each.value.name
  description             = each.value.description
  type                    = each.value.type
  cloud_provider          = var.astro_cloud_provider
  region                  = var.astro_region
  workspace_id            = astro_workspace.data_engineering.id
  contact_emails          = var.astro_contact_emails
  executor                = each.value.executor
  is_cicd_enforced        = each.value.is_cicd_enforced
  is_dag_deploy_enabled   = each.value.is_dag_deploy_enabled
  is_development_mode     = each.value.is_development_mode
  is_high_availability    = each.value.is_high_availability
  scheduler_size          = each.value.scheduler_size
  resource_quota_cpu      = each.value.resource_quota_cpu
  resource_quota_memory   = each.value.resource_quota_memory
  default_task_pod_cpu    = each.value.default_task_pod_cpu
  default_task_pod_memory = each.value.default_task_pod_memory

  environment_variables = [
    {
      key       = "ENVIRONMENT"
      value     = each.key
      is_secret = false
    },
    {
      key       = "AIRFLOW__CORE__DEFAULT_TIMEZONE"
      value     = "America/New_York"
      is_secret = false
    }
  ]

  # Only set scaling_spec if there are hibernation schedules
  scaling_spec = length(each.value.hibernation_schedules) > 0 ? {
    hibernation_spec = {
      schedules = [
        for schedule in each.value.hibernation_schedules : {
          hibernate_at_cron = schedule.hibernate_at_cron
          wake_at_cron      = schedule.wake_at_cron
          description       = schedule.description
          is_enabled        = schedule.is_enabled
        }
      ]
    }
  } : null

  lifecycle {
    prevent_destroy = true
  }
}

