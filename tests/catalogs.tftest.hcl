# The raw and dev catalogs, planned against mocked providers. These assert the
# shape of the two catalogs and the grants that are the whole point of them:
# raw holds every loader's output and is unreadable by analyst, and dev holds
# personal and CI work under the roles that may write it. A mistaken grant here
# is a data exposure that no other check in this repo would catch, and a plan
# against the real workspace cannot be run from a pull request.

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
  # Known at plan time so the assertions below can read principal names.
  mock_resource "databricks_service_principal" {
    defaults = {
      id             = "1234567890"
      application_id = "00000000-0000-0000-0000-000000000001"
    }
    override_during = plan
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
  mock_resource "databricks_service_principal" {
    defaults = {
      id             = "1234567890"
      application_id = "00000000-0000-0000-0000-000000000001"
    }
    override_during = plan
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

# The salt tag is imported from live state, and a mock provider cannot serve an
# import. Overriding it makes the import a no-op plan, which is all these tests
# need from it.
override_resource {
  target = databricks_entity_tag_assignment.pseudonym_salt_classified
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

run "raw_carries_a_terraformed_catalog_with_its_own_storage" {
  command = plan

  assert {
    condition     = databricks_catalog.raw.name == "raw"
    error_message = "The loader catalog must be named raw."
  }

  assert {
    condition     = databricks_catalog.raw.storage_root == "s3://example-bucket/raw"
    error_message = "raw must have its own storage root, or its tables land in the prod bucket."
  }

  assert {
    condition     = databricks_catalog.dev.name == "dev"
    error_message = "The personal and CI catalog must be named dev."
  }

  assert {
    condition     = databricks_catalog.dev.storage_root == "s3://example-bucket/dev"
    error_message = "dev must have its own storage root, or its tables land in the prod bucket."
  }
}

run "analyst_cannot_reach_raw" {
  command = plan

  assert {
    condition     = !contains(keys(local.raw_catalog_grants), "analyst")
    error_message = "analyst must hold nothing on raw. Every masked reader works above it."
  }

  assert {
    condition     = !anytrue([for k, v in local.raw_catalog_grants : v.principal == "account users" || v.principal == "data users"])
    error_message = "The general reader groups must hold nothing on raw; it is where the unmasked values live."
  }

  assert {
    condition     = !anytrue([for k, v in local.raw_catalog_grants : contains(v.privileges, "MANAGE")])
    error_message = "Nothing but Terraform manages raw's grants."
  }
}

run "raw_reads_in_the_clear_for_the_roles_that_must" {
  command = plan

  assert {
    condition = alltrue([
      for role in ["pii_viewer", "transformer", "dbt_cloud"] : contains(local.raw_catalog_grants[role].privileges, "SELECT")
    ])
    error_message = "pii_viewer, transformer and dbt_cloud all read raw in the clear; dbt builds staging from it."
  }

  assert {
    condition     = contains(local.raw_catalog_grants["ingestor"].privileges, "MODIFY")
    error_message = "ingestor writes raw, and MODIFY is what the loaders need."
  }

  assert {
    condition     = !contains(local.raw_catalog_grants["transformer"].privileges, "MODIFY")
    error_message = "transformer reads raw and writes prod; it has no business modifying raw."
  }
}

run "dev_holds_personal_and_ci_work" {
  command = plan

  assert {
    condition     = contains(local.dev_catalog_grants["analyst"].privileges, "CREATE_SCHEMA")
    error_message = "analyst creates the per-user personal schema on dev, and owns it."
  }

  assert {
    condition     = contains(local.dev_catalog_grants["transformer"].privileges, "CREATE_SCHEMA")
    error_message = "transformer creates the ci_<pr> schemas on dev."
  }

  assert {
    condition     = !contains(local.dev_catalog_grants["pii_viewer"].privileges, "CREATE_SCHEMA")
    error_message = "pii_<user> schemas are created by transformer; pii_viewer is a read role and needs no schema creation."
  }

  # Creating a schema does not let you use it, and analyst has to use the one it
  # creates on its own first run.
  assert {
    condition     = contains(local.dev_catalog_grants["analyst"].privileges, "USE_SCHEMA")
    error_message = "analyst must be able to use the personal schema it creates, or its first build fails."
  }

  # The ci_<pr> schemas are built and owned by dbt_cloud, which is the dbt
  # builder. github-action is read-only here, so granting it write would widen
  # what PR-triggered code can do for no reason.
  assert {
    condition = contains(local.dev_catalog_grants["dbt_cloud"].privileges, "CREATE_SCHEMA") && contains(
      local.dev_catalog_grants["dbt_cloud"].privileges, "CREATE_TABLE"
    )
    error_message = "dbt_cloud builds and owns the ci_<pr> schemas on dev."
  }

  assert {
    condition     = !contains(local.dev_catalog_grants["github_action"].privileges, "CREATE_TABLE")
    error_message = "github-action builds no dbt relation; it must not be able to write on dev."
  }

  assert {
    condition     = contains(local.dev_catalog_grants["dbt_cloud"].privileges, "CREATE_TABLE")
    error_message = "dbt Cloud materializes dev relations itself."
  }
}

# analyst is the masked role. A catalog-wide SELECT reached the raw sources, the
# CI and personal schemas and the pseudonym salt, so its read scope is an
# explicit list. Anything not on it is closed to analyst, and that is the point.
run "analyst_reads_only_the_prod_schemas_it_is_listed_on" {
  command = plan

  assert {
    condition = !anytrue(flatten([
      for grant in databricks_grants.catalog_main.grant : [
        for privilege in grant.privileges : grant.principal == databricks_group.role_analyst.display_name && contains(
          ["SELECT", "USE_SCHEMA"], privilege
        )
      ]
    ]))
    error_message = "analyst must hold neither SELECT nor USE_SCHEMA on the catalog: they reach every schema in it, raw and finance and the salt included. CREATE_SCHEMA is fine and required."
  }

  assert {
    condition = !anytrue([
      for grant in databricks_grants.mart_schemas[local.finance_mart].grant : grant.principal == databricks_group.role_analyst.display_name
    ])
    error_message = "analyst must hold nothing on the finance mart; its audience is business and finance ops."
  }

  assert {
    condition = contains(databricks_grant.analyst_dbt.privileges, "SELECT") && alltrue([
      for mart, grants in databricks_grants.mart_schemas : mart == local.finance_mart ? true : anytrue([
        for grant in grants.grant : grant.principal == databricks_group.role_analyst.display_name && contains(grant.privileges, "SELECT")
      ])
    ])
    error_message = "analyst reads the dbt schema and every mart except finance, and a mart that silently drops its analyst grant breaks the masked readers."
  }
}

# The catalog-wide read analyst gave up was shared with pii_viewer, which holds
# every role above it, and with the transformer nested inside pii_viewer.
run "the_unmasked_roles_keep_their_catalog_read" {
  command = plan

  assert {
    condition = anytrue([
      for grant in databricks_grants.catalog_main.grant : grant.principal == databricks_group.role_pii_viewer.display_name && alltrue(
        [for privilege in ["USE_SCHEMA", "SELECT"] : contains(grant.privileges, privilege)]
      )
    ])
    error_message = "pii_viewer holds the catalog-wide read, or it and the transformer nested inside it lose every schema analyst no longer reaches."
  }

  assert {
    condition = !anytrue(flatten([
      for grant in databricks_grants.catalog_main.grant : [
        for privilege in grant.privileges : grant.principal == databricks_group.role_ingestor.display_name && contains(
          ["SELECT", "USE_SCHEMA"], privilege
        )
      ]
    ]))
    error_message = "ingestor must hold no catalog read: it writes raw, and a catalog-wide SELECT would let any loader running as ingestor read the salt."
  }
}
