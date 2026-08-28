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

  # The general-purpose mart the gp-api application queries directly over SQL,
  # as its own service principal on its own warehouse. Holds whatever gp-api
  # needs served from Databricks; today that is the L2 voter-file pass-through.
  gp_api = {
    mart           = "gp_api"
    sp_name        = "gp_api"
    warehouse_name = "wh-gp-api"
  }

  # Marts that all data users should be able to read.
  # mban2026 is excluded: its reader group also grants write + CREATE_MODEL on
  # the models_mban schema, and it holds DEID voter data scoped to a cohort.
  # sales_reverse_etl is excluded: it holds PII-bearing candidate export feeds
  # (email, phone, street address). Read access is scoped to the
  # mart_sales_reverse_etl_readers group (biz-ops, assigned in the console; plus the
  # reverse-ETL service principal once DATA-1840 builds it), not all data users.
  # See DATA-2011.
  # gp_api is excluded: it passes the full L2 record through, PII included.
  # Only the gp-api service principal is in its group.
  shared_marts = { for k, v in local.marts_map : k => v if k != "mban2026" && k != "sales_reverse_etl" && k != local.gp_api.mart }

  # The Astronomer-managed workload identity per deployment (Deployment > Details >
  # Workload Identity). Every AWS role Airflow assumes trusts these.
  astro_workload_identities = {
    dev  = "arn:aws:iam::111928029897:role/astro-galactian-element-5125"
    prod = "arn:aws:iam::111928029897:role/astro-exothermic-astronaut-9119"
  }

  # Trust policy shared by every AWS role Airflow assumes: only this environment's
  # workload identity, gated by the per-env sts:ExternalId (confused-deputy guard).
  # The nonce is shared across roles in a deployment because it's the deployment
  # that presents it, not the role, so a per-role nonce would isolate nothing.
  astro_assume_role_policy = {
    for env, principal in local.astro_workload_identities : env => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Principal = { AWS = principal }
          Action    = "sts:AssumeRole"
          Condition = {
            StringEquals = {
              "sts:ExternalId" = var.astro_workload_external_ids[env]
            }
          }
        },
      ]
    })
  }

  # A dedicated queue for the L2 voter-file sync. Its tasks download a whole archive
  # (largest ~7 GB) to the worker's fixed 10 GiB of ephemeral storage, so a second
  # concurrent task on the same worker would exhaust the disk.
  l2_voter_files_worker_queue = {
    name               = "l2-voter-files"
    is_default         = false
    astro_machine      = "A5"
    min_worker_count   = 0
    max_worker_count   = 1
    worker_concurrency = 1
  }

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
        },
        local.l2_voter_files_worker_queue,
        {
          # sync_election_api routes its Databricks-to-Postgres load tasks here.
          # Each peaks near 400 MB, so an A5 fits two; the queue scales out on
          # queued-task count instead of packing more onto one worker.
          name               = "election-api-sync"
          is_default         = false
          astro_machine      = "A5"
          min_worker_count   = 0
          max_worker_count   = 7
          worker_concurrency = 2
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
        },
        local.l2_voter_files_worker_queue,
        {
          # sync_election_api routes its Databricks-to-Postgres load tasks here.
          # Each peaks near 400 MB, so an A5 fits two; the queue scales out on
          # queued-task count instead of packing more onto one worker.
          name               = "election-api-sync"
          is_default         = false
          astro_machine      = "A5"
          min_worker_count   = 0
          max_worker_count   = 7
          worker_concurrency = 2
        }
      ]
      hibernation_schedules = []
    }
  }
}
