# CI environment - includes both dev and prod for complete plan
# This file is used by GitHub Actions to plan all environments together

astro_environments = {
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
    hibernation_schedules = [
      {
        hibernate_at_cron = "0 1 * * 2,3,4,5,6"
        wake_at_cron      = "0 14 * * 1,2,3,4,5"
        description       = "Hibernate overnight, wake on weekday afternoons UTC"
        is_enabled        = true
      }
    ]
  }
  prod = {
    name                    = "astro-prod"
    description             = "Production Airflow environment"
    type                    = "STANDARD"
    executor                = "KUBERNETES"
    is_cicd_enforced        = false
    is_dag_deploy_enabled   = true
    is_development_mode     = false
    is_high_availability    = false
    default_task_pod_cpu    = "0.25"
    default_task_pod_memory = "0.5Gi"
    resource_quota_cpu      = "10"
    resource_quota_memory   = "20Gi"
    scheduler_size          = "SMALL"
    hibernation_schedules   = []
  }
}
