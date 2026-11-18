# The analyst masking policies. Three per catalog: identifiers hashed,
# confidential values nulled, and every table nobody has classified closed.
#
# The function bodies live in gp-data-platform and are built by dbt, not here. A
# policy that names a missing function fails to create, and a function or
# governed tag dropped while a policy still references it fails every query in
# the policy's scope. So the functions, the salt row and the tags all have to
# exist before a Deploy runs this file, and README carries that order.
#
# TO is the analyst group and nothing else. The four higher roles are nested
# inside it, so analyst's reach is all five, and EXCEPT pii_viewer takes
# pii_viewer and the transformer nested inside it back out. Note which roles that
# leaves masked: ingestor and admin are nested in analyst only, not in
# pii_viewer, so they are subject to these policies like analyst is. Nobody is in
# any of the five yet.
#
# pii_services and ingestor are deliberately absent from EXCEPT. The first does
# not exist yet and arrives in the catalog split, and a policy cannot name a
# principal that is not there. The second would be exempt from the masks on the
# marts as well as on raw, because one catalog still holds both; its raw-only
# exemption arrives with the raw catalog.
locals {
  column_mask_policies = {
    mask_identifier = {
      comment       = "Hash every column tagged sensitive=identifier, unless it carries the open tag."
      condition     = "has_tag_value('sensitive', 'identifier') and not has_tag('open')"
      function_name = "pseudonym"
    }
    mask_confidential = {
      comment       = "Null every column tagged sensitive=confidential, unless it carries the open tag."
      condition     = "has_tag_value('sensitive', 'confidential') and not has_tag('open')"
      function_name = "redact"
    }
  }
}

resource "databricks_policy_info" "mask_columns" {
  for_each = local.column_mask_policies

  on_securable_type     = "CATALOG"
  on_securable_fullname = databricks_catalog.main.name
  name                  = each.key
  comment               = each.value.comment

  policy_type        = "POLICY_TYPE_COLUMN_MASK"
  for_securable_type = "TABLE"
  to_principals      = [databricks_group.role_analyst.display_name]
  except_principals  = [databricks_group.role_pii_viewer.display_name]

  match_columns = [{
    condition = each.value.condition
    alias     = "c"
  }]

  column_mask = {
    function_name = "${databricks_catalog.main.name}.${databricks_schema.governance.name}.${each.value.function_name}"
    on_column     = "c"
  }

  lifecycle {
    prevent_destroy = true
  }

  # Creating a policy needs MANAGE on the securable and EXECUTE on the function,
  # and neither appears in the arguments above, so Terraform sees no dependency
  # of its own and is free to create the policies alongside the grant changes.
  depends_on = [
    databricks_grants.catalog_main,
    databricks_grants.governance,
  ]
}

# The row filter, on the table tag rather than on a column. A table with no
# classified tag returns no rows, so a new source lands closed and a table dbt
# just built stays closed until its tags propagate.
resource "databricks_policy_info" "closed_until_classified" {
  on_securable_type     = "CATALOG"
  on_securable_fullname = databricks_catalog.main.name
  name                  = "closed_until_classified"
  comment               = "A table returns no rows until it carries classified=true."

  policy_type        = "POLICY_TYPE_ROW_FILTER"
  for_securable_type = "TABLE"
  to_principals      = [databricks_group.role_analyst.display_name]
  except_principals  = [databricks_group.role_pii_viewer.display_name]

  when_condition = "not has_tag_value('classified', 'true')"

  row_filter = {
    function_name = "${databricks_catalog.main.name}.${databricks_schema.governance.name}.no_rows"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    databricks_grants.catalog_main,
    databricks_grants.governance,
  ]
}
