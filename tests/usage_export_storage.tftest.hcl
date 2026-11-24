# The usage export read path, planned against mocked providers. Two exporters write
# into one workbench bucket, and Unity Catalog reaches each through the same role
# and storage credential but its own external location. These assert the parts a
# real plan cannot check from a pull request: that the role reads both prefixes,
# that the two locations are siblings rather than one nested in the other, and that
# every airflow principal reads the new one.

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

# Known at plan so the grants can be pinned to the location they own: a mocked
# resource's id is otherwise unknown until apply, and this stack cannot apply in a
# pull request.
override_resource {
  target          = databricks_external_location.bifrost_usage
  override_during = plan
  values = {
    id = "bifrost_usage_export"
  }
}

override_resource {
  target          = databricks_external_location.delegate_swarm_usage
  override_during = plan
  values = {
    id = "delegate_swarm_usage_export"
  }
}

# The two airflow principals with distinct plan-time ids. Their application ids are
# computed from a live account, so without these the grant set's principals are
# unknown at plan and no test could pin who reads the location. The values are
# fake; what is asserted is that every principal in service_principals.tf's
# airflow set appears, and nothing else does.
override_resource {
  target          = databricks_service_principal.airflow["airflow"]
  override_during = plan
  values = {
    id             = "1111111111111111"
    application_id = "00000000-0000-0000-0000-0000000000a1"
  }
}

override_resource {
  target          = databricks_service_principal.airflow["airflow_dev"]
  override_during = plan
  values = {
    id             = "2222222222222222"
    application_id = "00000000-0000-0000-0000-0000000000a2"
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

run "the_role_reads_both_exporters_prefixes" {
  command = plan

  assert {
    condition = toset(
      jsondecode(aws_iam_role_policy.bifrost_usage.policy).Statement[0].Resource
      ) == toset([
        "arn:aws:s3:::goodparty-workbench-bifrost-usage/bifrost/logs/*",
        "arn:aws:s3:::goodparty-workbench-bifrost-usage/delegate-swarm/*",
    ])
    error_message = "The one reader role must cover both exporters' prefixes; a prefix missing here is an external location that fails validation at apply."
  }

  assert {
    condition = toset(
      jsondecode(aws_iam_role_policy.bifrost_usage.policy).Statement[2].Condition.StringLike["s3:prefix"]
      ) == toset([
        "bifrost/logs",
        "bifrost/logs/*",
        "delegate-swarm",
        "delegate-swarm/*",
    ])
    error_message = "Each location root and its contents must be listable, or Databricks cannot validate the location it is given."
  }
}

run "a_policy_change_reruns_the_iam_propagation_wait" {
  command = plan

  assert {
    condition     = time_sleep.bifrost_usage_iam_propagation.triggers["policy"] == sha256(aws_iam_role_policy.bifrost_usage.policy)
    error_message = "The wait is keyed to the policy document. depends_on alone does not rerun it on an update, so widening the policy and creating the new location in one apply would validate against stale IAM state."
  }
}

run "the_swarm_has_its_own_location_on_the_same_credential" {
  command = plan

  assert {
    condition     = databricks_external_location.delegate_swarm_usage.url == "s3://goodparty-workbench-bifrost-usage/delegate-swarm"
    error_message = "The swarm's export root is delegate-swarm, a sibling of bifrost/logs; nesting it inside the other location is refused by Unity Catalog."
  }

  assert {
    condition     = databricks_external_location.delegate_swarm_usage.credential_name == databricks_storage_credential.bifrost_usage.name && databricks_external_location.bifrost_usage.credential_name == databricks_storage_credential.bifrost_usage.name
    error_message = "Both locations share one credential, so one role and one trust admit the whole read path."
  }

  assert {
    condition     = databricks_external_location.delegate_swarm_usage.read_only
    error_message = "The loaders read; nothing in Databricks writes these prefixes."
  }
}

run "the_swarm_grants_sit_on_the_swarm_location" {
  command = plan

  assert {
    condition     = databricks_grants.delegate_swarm_usage_external_location.external_location == databricks_external_location.delegate_swarm_usage.id
    error_message = "The grant set must name the swarm location; a copy of the Bifrost block that kept its securable leaves this location unreadable."
  }

  assert {
    condition     = databricks_grants.bifrost_usage_external_location.external_location == databricks_external_location.bifrost_usage.id
    error_message = "The Bifrost grant set must still name the Bifrost location. Two grant sets on one securable fight on the next apply, and the other location stays unreadable."
  }
}

run "both_airflow_principals_read_the_swarm_location_and_no_one_else_does" {
  command = plan

  assert {
    condition = toset([
      for grant in databricks_grants.delegate_swarm_usage_external_location.grant : grant.principal
      ]) == toset([
      for key, sp in databricks_service_principal.airflow : sp.application_id
    ])
    error_message = "Every airflow principal and no other principal. The two are pinned by the override block above, so a narrowed loop fails here."
  }

  assert {
    condition = toset([
      for grant in databricks_grants.delegate_swarm_usage_external_location.grant : grant.principal
      ]) == toset([
      for grant in databricks_grants.bifrost_usage_external_location.grant : grant.principal
    ])
    error_message = "The same readers as the Bifrost location, since both land in one bucket and one loader runs as each."
  }

  assert {
    condition = alltrue([
      for grant in databricks_grants.delegate_swarm_usage_external_location.grant :
      contains(grant.privileges, "READ_FILES") && length(grant.privileges) == 1
    ])
    error_message = "READ_FILES and nothing else: COPY INTO is a read, and nothing in Databricks writes these prefixes."
  }
}
