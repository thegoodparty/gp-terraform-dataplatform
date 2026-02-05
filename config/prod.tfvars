# Prod environment configuration

astro_env_prod = {
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
