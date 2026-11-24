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
    condition     = databricks_external_location.delegate_swarm_usage.name != databricks_external_location.bifrost_usage.name
    error_message = "Two locations cannot share a name, and a copied block that kept the Bifrost name would collide on apply."
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
    error_message = "Two grant sets on one securable fight each other on the next apply, and the other location stays unreadable."
  }
}

run "read_files_is_the_only_privilege_any_airflow_principal_gets" {
  # Plan, not apply: a service principal's application id is computed, so neither
  # grant set's principal list is known here. The privileges are.
  command = plan

  assert {
    condition = alltrue([
      for grant in databricks_grants.delegate_swarm_usage_external_location.grant :
      contains(grant.privileges, "READ_FILES") && length(grant.privileges) == 1
    ])
    error_message = "READ_FILES and nothing else: COPY INTO is a read, and nothing in Databricks writes these prefixes."
  }

  assert {
    condition = alltrue([
      for grant in databricks_grants.bifrost_usage_external_location.grant :
      contains(grant.privileges, "READ_FILES") && length(grant.privileges) == 1
    ])
    error_message = "The Bifrost location's grant set must stay as it was, since the same principals read both."
  }
}
