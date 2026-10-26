# =============================================================================
# gp-api Postgres federation (Lakehouse Federation)
# =============================================================================
# A foreign catalog per environment reads gp-api's Aurora database live
# through a Unity Catalog connection. Serverless compute, which runs federated
# queries, reaches Aurora through a VPC endpoint service omni's Pulumi creates
# and a private endpoint rule on the workspace's NCC. The connections, the
# secret values and the Postgres role's password are made by hand (README),
# because a connection resource would put the password in state.

locals {
  gp_api_federation = {
    dev = {
      catalog       = "gp_api_pg_dev"
      readers_group = "gp_api_pg_dev_readers"
      host          = "gp-api-db.cluster-cmb1uukjsfbe.us-west-2.rds.amazonaws.com"
    }
    prod = {
      catalog       = "gp_api_pg"
      readers_group = "gp_api_pg_readers"
      host          = "gp-api-db-prod.cluster-cmb1uukjsfbe.us-west-2.rds.amazonaws.com"
    }
  }

  gp_api_federation_connected = {
    for env, endpoint_service in var.gp_api_federation_envs :
    env => merge(local.gp_api_federation[env], { endpoint_service = endpoint_service })
  }
}

# Holds postgres-password, which the connection resolves with secret(). The
# value is put by hand and never passes through Terraform.
resource "databricks_secret_scope" "gp_api_federation" {
  for_each = local.gp_api_federation
  name     = "gp-api-federation-${each.key}"
}

# One readers group per foreign catalog. Not nested into data users: the
# catalog exposes users' personal data, so membership is assigned in the
# console.
resource "databricks_group" "gp_api_pg_readers" {
  for_each     = local.gp_api_federation
  provider     = databricks.account
  display_name = each.value.readers_group

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "gp_api_pg_readers" {
  for_each     = local.gp_api_federation
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.gp_api_pg_readers[each.key].id
  permissions  = ["USER"]
}

# A workspace takes one NCC, and this is ours. Add future serverless private
# endpoint rules here; binding another NCC would drop these rules.
resource "databricks_mws_network_connectivity_config" "workspace" {
  provider = databricks.account
  name     = "goodparty-us-west-2"
  region   = "us-west-2"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_ncc_binding" "workspace" {
  provider                       = databricks.account
  network_connectivity_config_id = databricks_mws_network_connectivity_config.workspace.network_connectivity_config_id
  workspace_id                   = var.workspace_id
}

# Everything below needs the env's endpoint service and connection, so an env
# joins gp_api_federation_envs only once both exist.

# Starts PENDING until an AWS admin accepts the VPC endpoint on the endpoint
# service. The domain name must match the connection's host.
resource "databricks_mws_ncc_private_endpoint_rule" "gp_api_federation" {
  for_each                       = local.gp_api_federation_connected
  provider                       = databricks.account
  network_connectivity_config_id = databricks_mws_network_connectivity_config.workspace.network_connectivity_config_id
  endpoint_service               = each.value.endpoint_service
  domain_names                   = [each.value.host]

  depends_on = [databricks_mws_ncc_binding.workspace]
}

# Creating a foreign catalog takes CREATE_FOREIGN_CATALOG on the connection;
# USE_CONNECTION lets CI read it. Querying the catalog on serverless needs only
# catalog privileges, so gp_api gets no connection grant. Singular grants
# because databricks_grants rejects connection privileges:
# databricks/terraform-provider-databricks#5398.
resource "databricks_grant" "gp_api_federation_connection_github_action" {
  for_each           = local.gp_api_federation_connected
  foreign_connection = "gp_api_${each.key}"
  principal          = data.databricks_service_principal.github_action.application_id
  privileges         = ["USE_CONNECTION", "CREATE_FOREIGN_CATALOG"]
}

resource "databricks_catalog" "gp_api_pg" {
  for_each        = local.gp_api_federation_connected
  name            = each.value.catalog
  connection_name = "gp_api_${each.key}"
  comment         = "Live, read-only view of gp-api Postgres (${each.key}) through Lakehouse Federation. Holds users' personal data; grant access deliberately."
  # The catalog holds only mirrored metadata, so a cascading drop deletes no
  # data, and without it a synced catalog refuses to drop.
  force_destroy = true

  options = {
    database = "gpdb"
  }

  depends_on = [
    databricks_grant.gp_api_federation_connection_github_action,
    databricks_mws_ncc_private_endpoint_rule.gp_api_federation,
  ]
}

resource "databricks_grants" "gp_api_pg" {
  for_each = local.gp_api_federation_connected
  catalog  = databricks_catalog.gp_api_pg[each.key].name

  grant {
    principal  = databricks_group.gp_api_pg_readers[each.key].display_name
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }

  # One SP serves gp-api dev and prod, so it reads both catalogs.
  grant {
    principal  = databricks_service_principal.gp_api.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
}
