# =============================================================================
# gp-api Postgres federation (Lakehouse Federation)
# =============================================================================
# A foreign catalog per environment reads gp-api's Aurora database live
# through a Unity Catalog connection. Serverless compute, which runs federated
# queries, reaches Aurora through an internet-facing NLB in front of an RDS
# Proxy, which omni's Pulumi creates and allowlists to Databricks' outbound
# IPs, so nothing here configures the network. The connections, the secret values and the Postgres
# role's password are made by hand (README), because a connection resource
# would put the password in state.

locals {
  gp_api_federation = {
    dev = {
      catalog       = "gp_api_pg_dev"
      readers_group = "gp_api_pg_dev_readers"
    }
    prod = {
      catalog       = "gp_api_pg"
      readers_group = "gp_api_pg_readers"
    }
  }

  gp_api_federation_connected = {
    for env in toset(var.gp_api_federation_envs) : env => local.gp_api_federation[env]
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

# Everything below needs the env's connection, so both connections exist
# before Deploy.

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

  depends_on = [databricks_grant.gp_api_federation_connection_github_action]
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
