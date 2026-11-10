# Governance roles (Unity Catalog RBAC). Each role is an account-level group that
# a person or job assumes for a session. Nesting means a role carries the
# privileges of every role it contains.
#
# Terraform owns the role groups, their nesting and their catalog grants. People
# are not added here: membership and assume rules are managed separately.

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

# pii_viewer is analyst plus raw access; transformer is pii_viewer plus write.
resource "databricks_group_member" "analyst_in_pii_viewer" {
  provider  = databricks.account
  group_id  = databricks_group.role_pii_viewer.id
  member_id = databricks_group.role_analyst.id
}

resource "databricks_group_member" "pii_viewer_in_transformer" {
  provider  = databricks.account
  group_id  = databricks_group.role_transformer.id
  member_id = databricks_group.role_pii_viewer.id
}

resource "databricks_group_member" "analyst_in_ingestor" {
  provider  = databricks.account
  group_id  = databricks_group.role_ingestor.id
  member_id = databricks_group.role_analyst.id
}

resource "databricks_group_member" "analyst_in_admin" {
  provider  = databricks.account
  group_id  = databricks_group.role_admin.id
  member_id = databricks_group.role_analyst.id
}

# Role groups are assigned to the workspace so they can be assumed there.
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
