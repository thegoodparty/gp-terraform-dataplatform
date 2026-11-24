# Governance roles (Unity Catalog RBAC). A role is an account-level group that a
# person or job assumes for a session. A higher role joins a lower one and
# inherits its privileges.
#
# Assume permission is granted outside Terraform (account rule sets), so that
# nothing here overwrites a live grant. People are not added here either.

resource "databricks_group" "role_analyst" {
  provider     = databricks.account
  display_name = "analyst"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_group" "role_pii_viewer" {
  provider     = databricks.account
  display_name = "pii_viewer"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_group" "role_transformer" {
  provider     = databricks.account
  display_name = "transformer"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_group" "role_ingestor" {
  provider     = databricks.account
  display_name = "ingestor"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_group" "role_admin" {
  provider     = databricks.account
  display_name = "admin"

  lifecycle {
    prevent_destroy = true
  }
}

# A member inherits the group's privileges, so the higher role is the member.
resource "databricks_group_member" "pii_viewer_in_analyst" {
  provider  = databricks.account
  group_id  = databricks_group.role_analyst.id
  member_id = databricks_group.role_pii_viewer.id
}

resource "databricks_group_member" "transformer_in_pii_viewer" {
  provider  = databricks.account
  group_id  = databricks_group.role_pii_viewer.id
  member_id = databricks_group.role_transformer.id
}

# dbt Cloud's prod builds run as dbt_cloud, so it holds transformer's rights.
resource "databricks_group_member" "dbt_cloud_in_transformer" {
  provider  = databricks.account
  group_id  = databricks_group.role_transformer.id
  member_id = data.databricks_service_principal.dbt_cloud.id
}

resource "databricks_group_member" "ingestor_in_analyst" {
  provider  = databricks.account
  group_id  = databricks_group.role_analyst.id
  member_id = databricks_group.role_ingestor.id
}

resource "databricks_group_member" "admin_in_analyst" {
  provider  = databricks.account
  group_id  = databricks_group.role_analyst.id
  member_id = databricks_group.role_admin.id
}

# The platform admins set up Databricks ingestion pipelines, which write raw as
# the person running them, so they take ingestor's write rights on raw. Already
# added in the console; creating a membership that exists is a no-op SCIM add.
# ingestor also writes prod, but the admin group owns the metastore, so it
# already holds every right on prod; this adds nothing there.
resource "databricks_group_member" "admin_group_in_ingestor" {
  provider  = databricks.account
  group_id  = databricks_group.role_ingestor.id
  member_id = data.databricks_group.admin_group.id
}

# Assigns the roles to the workspace (visibility only). Assume is granted separately.
resource "databricks_mws_permission_assignment" "role_groups" {
  for_each = {
    analyst     = databricks_group.role_analyst.id
    pii_viewer  = databricks_group.role_pii_viewer.id
    transformer = databricks_group.role_transformer.id
    ingestor    = databricks_group.role_ingestor.id
    admin       = databricks_group.role_admin.id
  }
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = each.value
  permissions  = ["USER"]
}
