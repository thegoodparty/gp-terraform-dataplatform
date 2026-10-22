# =============================================================================
# gp-api Postgres mirror (Lakeflow Connect)
# =============================================================================
# A gateway reads gp-api's Aurora replication slot and an ingestion pipeline
# copies schema public into one mirror schema per environment. The Unity
# Catalog connections, the secret value, the Aurora role's password and the
# replication slot are made by hand (README), because a connection resource
# would put the Postgres password in state.

locals {
  gp_api_mirror = {
    dev = {
      schema        = "gp_api_mirror_dev"
      readers_group = "gp_api_mirror_dev_readers"
    }
    prod = {
      schema        = "gp_api_mirror"
      readers_group = "gp_api_mirror_readers"
    }
  }

  gp_api_mirror_connected = {
    for env, mirror in local.gp_api_mirror : env => mirror
    if contains(var.gp_api_mirror_connected_envs, env)
  }
}

resource "databricks_service_principal" "gp_api_mirror" {
  provider     = databricks.account
  display_name = "sp_gp_api_mirror"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "gp_api_mirror" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.gp_api_mirror.id
  permissions  = ["USER"]
}

# The gateway runs on classic compute, which needs unrestricted cluster
# creation. Entitlements of an account-level principal are set per workspace.
resource "databricks_entitlements" "gp_api_mirror" {
  service_principal_id = databricks_service_principal.gp_api_mirror.id
  allow_cluster_create = true

  depends_on = [databricks_mws_permission_assignment.gp_api_mirror]
}

# One readers group per mirror schema, as with the marts. Not nested into data
# users: the mirror holds users' personal data, so membership is assigned in
# the console.
resource "databricks_group" "gp_api_mirror_readers" {
  for_each     = local.gp_api_mirror
  provider     = databricks.account
  display_name = each.value.readers_group

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "gp_api_mirror_readers" {
  for_each     = local.gp_api_mirror
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.gp_api_mirror_readers[each.key].id
  permissions  = ["USER"]
}

resource "databricks_schema" "gp_api_mirror" {
  for_each     = local.gp_api_mirror
  catalog_name = databricks_catalog.main.name
  name         = each.value.schema
  comment      = "Lakeflow Connect mirror of gp-api Postgres (${each.key}), schema public. Holds users' personal data; grant SELECT deliberately. Timestamps without time zone are strings here."

  properties = {
    managed_by = "terraform"
    purpose    = "mirror"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# The gateway's staging volume and both event logs live in the mirror schema
# beside the tables, so the pipelines' principal writes all three.
resource "databricks_grants" "gp_api_mirror_schema" {
  for_each = local.gp_api_mirror
  schema   = databricks_schema.gp_api_mirror[each.key].id

  grant {
    principal  = databricks_group.gp_api_mirror_readers[each.key].display_name
    privileges = ["USE_SCHEMA", "SELECT"]
  }

  grant {
    principal = databricks_service_principal.gp_api_mirror.application_id
    privileges = [
      "USE_SCHEMA",
      "CREATE_TABLE",
      "CREATE_VOLUME",
      "MODIFY",
      "SELECT",
      "READ_VOLUME",
      "WRITE_VOLUME",
    ]
  }
}

# Holds postgres-password, which create-connection.sh resolves inside
# Databricks. The value is put by hand and never passes through Terraform.
resource "databricks_secret_scope" "gp_api_mirror" {
  for_each = local.gp_api_mirror
  name     = "gp-api-lakeflow-${each.key}"
}

resource "databricks_secret_acl" "gp_api_mirror_admin" {
  for_each   = local.gp_api_mirror
  scope      = databricks_secret_scope.gp_api_mirror[each.key].name
  principal  = data.databricks_group.admin_group.display_name
  permission = "MANAGE"
}

# Everything below needs the connection, and a continuous gateway starts the
# moment it is created, so an env joins gp_api_mirror_connected_envs only once
# its connection and replication slot exist.

# Databricks requires USE_CONNECTION of whoever creates the pipelines (this
# repo's CI, as github-action) as well as of the principal they run as.
resource "databricks_grants" "gp_api_mirror_connection" {
  for_each           = local.gp_api_mirror_connected
  foreign_connection = "gp_api_${each.key}_lakeflow"

  grant {
    principal  = databricks_service_principal.gp_api_mirror.application_id
    privileges = ["USE_CONNECTION"]
  }

  grant {
    principal  = data.databricks_service_principal.github_action.application_id
    privileges = ["USE_CONNECTION"]
  }
}

resource "databricks_pipeline" "gp_api_mirror_gateway" {
  for_each = local.gp_api_mirror_connected
  name     = "gp-api-mirror-${each.key}-gateway"
  catalog  = databricks_catalog.main.name
  schema   = databricks_schema.gp_api_mirror[each.key].name
  channel  = "CURRENT"
  # A stopped gateway leaves the slot unread, and Aurora keeps every change
  # log segment until it is read.
  continuous = true
  serverless = false

  gateway_definition {
    connection_name         = "gp_api_${each.key}_lakeflow"
    gateway_storage_catalog = databricks_catalog.main.name
    gateway_storage_schema  = databricks_schema.gp_api_mirror[each.key].name
    gateway_storage_name    = "gateway_staging"
  }

  # 8 vCPUs on the driver is the gateway minimum Databricks documents; the
  # worker does no work, so it is the smallest.
  cluster {
    label               = "default"
    driver_node_type_id = "m5.2xlarge"
    node_type_id        = "m5.large"
    num_workers         = 1
  }

  event_log {
    catalog = databricks_catalog.main.name
    schema  = databricks_schema.gp_api_mirror[each.key].name
    name    = "gateway_event_log"
  }

  notification {
    email_recipients = var.gp_api_mirror_notification_emails
    alerts = [
      "on-update-failure",
      "on-update-fatal-failure",
      "on-flow-failure",
    ]
  }

  run_as {
    service_principal_name = databricks_service_principal.gp_api_mirror.application_id
  }

  depends_on = [
    databricks_grants.gp_api_mirror_connection,
    databricks_grants.gp_api_mirror_schema,
    databricks_entitlements.gp_api_mirror,
  ]
}

resource "databricks_pipeline" "gp_api_mirror_ingestion" {
  for_each   = local.gp_api_mirror_connected
  name       = "gp-api-mirror-${each.key}-ingestion"
  catalog    = databricks_catalog.main.name
  schema     = databricks_schema.gp_api_mirror[each.key].name
  channel    = "CURRENT"
  serverless = true

  ingestion_definition {
    ingestion_gateway_id = databricks_pipeline.gp_api_mirror_gateway[each.key].id
    source_type          = "POSTGRESQL"

    objects {
      schema {
        source_catalog      = "gpdb"
        source_schema       = "public"
        destination_catalog = databricks_catalog.main.name
        destination_schema  = databricks_schema.gp_api_mirror[each.key].name
      }
    }

    # gp-api's Prisma migration creates the publication; the DB admin creates
    # the slot.
    source_configurations {
      catalog {
        source_catalog = "gpdb"
        postgres {
          slot_config {
            slot_name        = "databricks_lakeflow"
            publication_name = "databricks_lakeflow"
          }
        }
      }
    }

    table_configuration {
      scd_type = "SCD_TYPE_1"
      # Renames, type changes and primary key changes re-copy the table
      # instead of stopping it.
      auto_full_refresh_policy {
        enabled            = true
        min_interval_hours = 1
      }
    }
  }

  event_log {
    catalog = databricks_catalog.main.name
    schema  = databricks_schema.gp_api_mirror[each.key].name
    name    = "ingestion_event_log"
  }

  notification {
    email_recipients = var.gp_api_mirror_notification_emails
    alerts = [
      "on-update-fatal-failure",
      "on-flow-failure",
    ]
  }

  run_as {
    service_principal_name = databricks_service_principal.gp_api_mirror.application_id
  }
}

# The PostgreSQL ingestion pipeline cannot run in continuous mode, so this job
# runs it back to back instead.
resource "databricks_job" "gp_api_mirror_ingestion_loop" {
  for_each            = local.gp_api_mirror_connected
  name                = "gp-api-mirror-${each.key}-ingestion-loop"
  max_concurrent_runs = 1

  continuous {
    pause_status = "UNPAUSED"
  }

  email_notifications {
    on_failure                = var.gp_api_mirror_notification_emails
    no_alert_for_skipped_runs = true
  }

  task {
    task_key = "ingest"
    pipeline_task {
      pipeline_id = databricks_pipeline.gp_api_mirror_ingestion[each.key].id
    }
  }

  run_as {
    service_principal_name = databricks_service_principal.gp_api_mirror.application_id
  }
}

resource "databricks_permissions" "gp_api_mirror_gateway" {
  for_each    = local.gp_api_mirror_connected
  pipeline_id = databricks_pipeline.gp_api_mirror_gateway[each.key].id

  access_control {
    group_name       = data.databricks_group.admin_group.display_name
    permission_level = "CAN_MANAGE"
  }
}

resource "databricks_permissions" "gp_api_mirror_ingestion" {
  for_each    = local.gp_api_mirror_connected
  pipeline_id = databricks_pipeline.gp_api_mirror_ingestion[each.key].id

  access_control {
    group_name       = data.databricks_group.admin_group.display_name
    permission_level = "CAN_MANAGE"
  }
}

resource "databricks_permissions" "gp_api_mirror_ingestion_loop" {
  for_each = local.gp_api_mirror_connected
  job_id   = databricks_job.gp_api_mirror_ingestion_loop[each.key].id

  access_control {
    group_name       = data.databricks_group.admin_group.display_name
    permission_level = "CAN_MANAGE"
  }
}
