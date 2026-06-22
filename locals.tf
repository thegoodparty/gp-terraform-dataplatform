locals {
  marts_config = yamldecode(file("${path.module}/config/marts.yaml"))
  marts        = local.marts_config.marts

  marts_map = { for mart in local.marts : mart.name => mart }

  # Win and Serve product agents: mart, service principal, and warehouse (TDD DATA-1977).
  agent_products = {
    serve = {
      mart           = "serve_agents"
      sp_name        = "sp_serve_agent"
      warehouse_name = "wh-serve-agents"
    }
    win = {
      mart           = "win_agents"
      sp_name        = "sp_win_agent"
      warehouse_name = "wh-win-agents"
    }
  }

  # Marts that all data users should be able to read.
  # mban2026 is excluded: its reader group also grants write + CREATE_MODEL on
  # the models_mban schema, and it holds DEID voter data scoped to a cohort.
  # sales_reverse_etl is excluded: it holds PII-bearing candidate export feeds
  # (email, phone, street address). Read access is scoped to the
  # mart_sales_reverse_etl_readers group (biz-ops, assigned in the console; plus the
  # reverse-ETL service principal once DATA-1840 builds it), not all data users.
  # See DATA-2011.
  shared_marts = { for k, v in local.marts_map : k => v if k != "mban2026" && k != "sales_reverse_etl" }

  # Astro deployment environments
  # Both dev and prod Airflow environments live in our single infrastructure
  astro_environments = {
    dev = {
      name                    = "astro-dev"
      description             = "Development Airflow environment"
      type                    = "STANDARD"
      executor                = "ASTRO"
      is_cicd_enforced        = false
      is_dag_deploy_enabled   = true
      is_development_mode     = true
      is_high_availability    = false
      default_task_pod_cpu    = "0.25"
      default_task_pod_memory = "0.5Gi"
      resource_quota_cpu      = "10"
      resource_quota_memory   = "20Gi"
      scheduler_size          = "SMALL"
      worker_queues = [
        {
          name               = "default"
          is_default         = true
          astro_machine      = "A5"
          min_worker_count   = 0
          max_worker_count   = 10
          worker_concurrency = 5
        }
      ]
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
      executor                = "ASTRO"
      is_cicd_enforced        = false
      is_dag_deploy_enabled   = true
      is_development_mode     = false
      is_high_availability    = false
      default_task_pod_cpu    = "0.25"
      default_task_pod_memory = "0.5Gi"
      resource_quota_cpu      = "10"
      resource_quota_memory   = "20Gi"
      scheduler_size          = "SMALL"
      worker_queues = [
        {
          name               = "default"
          is_default         = true
          astro_machine      = "A5"
          min_worker_count   = 0
          max_worker_count   = 10
          worker_concurrency = 5
        }
      ]
      hibernation_schedules   = []
    }
  }
}
