# Account-level governed tags. A tag policy fixes the allowed values, so an
# ABAC policy can match on the tag without also trusting every writer to spell
# the value right.
#
# Propagation is not a Terraform or API setting: it is turned on per tag in the
# console under Catalog > Govern > Governed Tags > Configure, and README says so.
locals {
  governed_tags = {
    sensitive = {
      description = "Column sensitivity. identifier is hashed for a masked reader, confidential is nulled."
      values      = ["identifier", "confidential"]
    }
    classified = {
      description = "Set on a table once it has been reviewed, so the unclassified row filter lets it through."
      values      = ["true"]
    }
    open = {
      description = "Marks a column open by design, overriding a propagated sensitivity tag."
      values      = ["true"]
    }
  }
}

resource "databricks_tag_policy" "governed" {
  for_each    = local.governed_tags
  tag_key     = each.key
  description = each.value.description
  values      = [for v in each.value.values : { name = v }]

  lifecycle {
    prevent_destroy = true
  }
}

# Authoritative for a tag's whole rule set, so every entry this tag should have
# is declared here. The creator is written in as manager automatically at
# creation; declaring it means an apply neither drops it by accident nor depends
# on an invisible auto-write.
#
# ASSIGN is what makes a governed tag writable. Every write needs it, including
# re-setting a value that is already there, and dbt re-sets its tags on every
# build, so the build principal must hold it from the moment the tag exists.
# Only tag rule sets are managed here: group rule sets stay out of Terraform.
#
# No prevent_destroy: the name interpolates the tag policy id, which the provider
# treats as unknown on any tag update, so editing a tag forces this resource to
# be replaced. Blocking the destroy would fail the apply instead of re-creating
# the rule set, and a rule set with no ASSIGN stops every dbt build. Losing the
# rule set is recoverable on the next apply; losing the apply is not.
resource "databricks_access_control_rule_set" "governed" {
  for_each = local.governed_tags
  provider = databricks.account

  name = "accounts/${var.databricks_account_id}/tagPolicies/${databricks_tag_policy.governed[each.key].id}/ruleSets/default"

  grant_rules {
    principals = [data.databricks_service_principal.github_action.acl_principal_id]
    role       = "roles/tagPolicy.manager"
  }

  grant_rules {
    principals = [data.databricks_service_principal.dbt_cloud.acl_principal_id]
    role       = "roles/tagPolicy.assigner"
  }
}
