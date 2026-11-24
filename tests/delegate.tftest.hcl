# The delegate service principal (DATA-2768), planned against mocked providers.
# Its whole access surface today is two things: a workspace assignment, and
# CAN_USE on the shared Starter warehouse. It deliberately joins no group until
# analyst membership is verified separately, so the warehouse ACL is the only
# grant the plumbing depends on, and a plan against the real workspace cannot be
# run from a pull request.

mock_provider "databricks" {
  mock_data "databricks_service_principal" {
    defaults = {
      id               = "1234567890"
      application_id   = "00000000-0000-0000-0000-000000000001"
      acl_principal_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "databricks_group" {
    defaults = {
      id = "1234567890"
    }
  }
  mock_data "databricks_sql_warehouse" {
    defaults = {
      id = "abcdef1234567890"
    }
  }
  mock_data "databricks_external_location" {
    defaults = {
      id = "db_s3_external_databricks-s3-ingest-dbca4"
    }
  }
  mock_data "databricks_current_user" {
    defaults = {
      id = "1234567890"
    }
  }
  mock_data "databricks_metastore" {
    defaults = {
      id = "1234567890"
    }
  }
}

mock_provider "databricks" {
  alias = "account"
  mock_data "databricks_service_principal" {
    defaults = {
      id               = "1234567890"
      application_id   = "00000000-0000-0000-0000-000000000001"
      acl_principal_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "databricks_group" {
    defaults = {
      id = "1234567890"
    }
  }
  mock_data "databricks_user" {
    defaults = {
      id = "1234567890"
    }
  }
}

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-west-1"
    }
  }
}

mock_provider "astro" {}

override_resource {
  target = databricks_sql_endpoint.sigma
}

override_resource {
  target = databricks_schema.model_predictions
}

# A created SP's id and application_id are unknown until apply, and this stack
# cannot be applied against mocks (an mws_permission_assignment wants a numeric
# principal id, which the mocked SP ids are not). Fixing the ids of the SPs on
# the Starter ACL during plan makes every access_control entry known at plan
# time, so the assertion below decides on the ACL rather than on an unknown.
override_resource {
  target          = databricks_service_principal.delegate
  override_during = plan
  values = {
    id             = "1234567890"
    application_id = "00000000-0000-0000-0000-0000000000de"
  }
}

override_resource {
  target          = databricks_service_principal.segment_storage
  override_during = plan
  values = {
    id             = "1234567890"
    application_id = "00000000-0000-0000-0000-0000000000a1"
  }
}

override_resource {
  target          = databricks_service_principal.product_analytics
  override_during = plan
  values = {
    id             = "1234567890"
    application_id = "00000000-0000-0000-0000-0000000000a2"
  }
}

override_resource {
  target          = databricks_service_principal.airflow
  override_during = plan
  values = {
    id             = "1234567890"
    application_id = "00000000-0000-0000-0000-0000000000a3"
  }
}

variables {
  databricks_account_id             = "00000000-0000-0000-0000-000000000000"
  workspace_id                      = "0000000000000000"
  catalog_storage_bucket            = "s3://example-bucket"
  astro_organization_id             = "org_test"
  astro_contact_emails              = ["alerts@example.com"]
  gp_api_mirror_notification_emails = ["alerts@example.com"]
  astro_workload_external_ids       = { dev = "anon-dev", prod = "anon-prod" }
}

run "delegate_can_use_the_starter_warehouse" {
  command = plan

  assert {
    condition     = databricks_service_principal.delegate.display_name == "sp_delegate"
    error_message = "The delegate SP is named sp_delegate; everything that looks it up does so by name."
  }

  # Warehouse access is by role, so the analyst entry is what delegate's access will
  # depend on once it joins. Pinning it here means a later membership PR cannot
  # find the grant missing. The workspace users group also holds CAN_USE, so this
  # covers the window before that membership lands. The name is spelled out rather
  # than read from the group, so renaming the role fails here instead of quietly
  # renaming the grant with it.
  assert {
    condition = anytrue([
      for ac in databricks_permissions.sql_warehouse_starter.access_control :
      ac.group_name == "analyst" && ac.permission_level == "CAN_USE"
    ])
    error_message = "The Starter warehouse ACL must name the analyst role group at CAN_USE."
  }
}

# delegate is created with no group membership on purpose, so that a plumbing
# failure at follow-up wiring time cannot be mistaken for an access failure, and
# so that it reads no data before it joins analyst. Membership is asserted by
# scanning the sources, because a databricks_group_member's ids are unknown at
# plan time and an assert on the resources themselves cannot be evaluated
# against mocks.
#
# The scan is a file allowlist, not an inspection of individual resource blocks,
# because block matching misses a membership assembled elsewhere: a map for_each,
# an interpolated member_id, or ids threaded through a locals map in a second
# file all evade it. Instead, the set of root files allowed to name the delegate
# SP at all is fixed here, and none of those files may contain a group member. A
# membership has to name the principal somewhere, so any new mention lands on a
# file outside the list and fails closed.
run "delegate_joins_no_group" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.root, "*.tf") :
      !strcontains(file("${path.root}/${f}"), "databricks_service_principal.delegate") ||
      contains(["outputs.tf", "permissions.tf", "service_principals.tf"], f)
    ])
    error_message = "Only outputs.tf, permissions.tf and service_principals.tf may name databricks_service_principal.delegate; a membership built elsewhere would land in another file."
  }

  assert {
    condition = alltrue([
      for f in ["outputs.tf", "permissions.tf", "service_principals.tf"] :
      !strcontains(file("${path.root}/${f}"), "databricks_group_member")
    ])
    error_message = "No file that names the delegate SP may also hold a databricks_group_member; its analyst membership comes in a later PR."
  }
}
