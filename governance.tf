# The masking functions' home, and the salt they hash with. The functions
# themselves are built by dbt from gp-data-platform, as service principal
# objects rather than hand-run DDL.
#
# Terraform owns this schema, its grants and the salt table; dbt_cloud owns the
# functions it creates inside it.

resource "databricks_schema" "governance" {
  catalog_name = databricks_catalog.main.name
  name         = "governance"
  comment      = "Masking and row-filter functions used by ABAC policies, plus the versioned pseudonym salt."

  properties = {
    managed_by = "terraform"
    purpose    = "governance"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [databricks_grants.catalog_main]
}

# Terraform owns this table and no dbt model selects it, so no build can
# recreate it. A dbt build --full-refresh over a dbt-built salt table would drop
# the row and silently null every pseudonym, with no error anywhere.
#
# The salt value is generated inside Databricks after the first apply; README
# has the statement. Nothing seeds it from a workstation and no check prints it:
# every read is a count or a length.
resource "databricks_sql_table" "pseudonym_salt" {
  name         = "pseudonym_salt"
  catalog_name = databricks_catalog.main.name
  schema_name  = databricks_schema.governance.name
  table_type   = "MANAGED"
  comment      = "Versioned pseudonym salt. Generated in-cluster; never printed, never in version control."

  column {
    name = "version"
    type = "int"
  }

  column {
    name = "salt"
    type = "string"
  }

  # Without this the provider spins up its own classic cluster to run the DDL,
  # which a serverless-only workspace cannot do and which nobody would own.
  warehouse_id = data.databricks_sql_warehouse.starter.id

  lifecycle {
    prevent_destroy = true
  }
}

# The identifier mask reads this table, and Databricks refuses a mask that reads a
# table with its own row filter. Unclassified, the closed_until_classified
# filter lands here and every identifier column fails for a masked reader with
# UNSUPPORTED_NESTED_ROW_OR_COLUMN_ACCESS_POLICY. Classifying it lifts the filter.
#
# Applying it by hand on 2026-11-24 fixed the mask, but left the table held by
# grants alone, and analyst's catalog-wide SELECT reached it. Safe to declare
# now that the allowlist has taken that SELECT away and left analyst with
# USE_SCHEMA and EXECUTE on this schema only: a masked read through pseudonym
# still works, and a direct select of the salt is refused.
import {
  to = databricks_entity_tag_assignment.pseudonym_salt_classified
  id = "tables,${databricks_catalog.main.name}.${databricks_schema.governance.name}.pseudonym_salt,classified"
}

resource "databricks_entity_tag_assignment" "pseudonym_salt_classified" {
  entity_type = "tables"
  entity_name = "${databricks_catalog.main.name}.${databricks_schema.governance.name}.${databricks_sql_table.pseudonym_salt.name}"
  tag_key     = "classified"
  tag_value   = "true"

  depends_on = [
    databricks_tag_policy.governed,
    # The tag lifts the row filter, so it must not land before analyst has lost
    # its catalog-wide SELECT.
    databricks_grants.catalog_main,
  ]
}

# Authoritative, and safe here: this schema is created by this stack, and the
# only other writer is dbt_cloud's own builds.
#
# CREATE_FUNCTION is deliberately not on dbt_cloud's catalog grant, so the build
# principal needs it at the schema. Analyst gets EXECUTE so a person or agent
# working as analyst can run governance.pseudonym(...) to look a row up; the
# higher roles inherit it through nesting.
#
# Analyst holds USE_SCHEMA and EXECUTE and no SELECT, so it reads the functions
# and not the salt. The salt's tag lifts the row filter, which leaves grants as
# the only thing between a masked reader and the salt. data-engineers, dbt_cloud,
# github-action and the airflow principals read it through their catalog-level
# grants, and so does pii_viewer, which is unmasked by design.
resource "databricks_grants" "governance" {
  schema = databricks_schema.governance.id

  grant {
    principal  = data.databricks_service_principal.dbt_cloud.application_id
    privileges = ["USE_SCHEMA", "CREATE_FUNCTION"]
  }

  grant {
    principal  = databricks_group.role_analyst.display_name
    privileges = ["USE_SCHEMA", "EXECUTE"]
  }

  # Creating a policy needs EXECUTE on the function it names. github-action owns
  # this schema through Terraform but not the functions dbt builds inside it, so
  # the grant is explicit rather than implied by ownership.
  grant {
    principal  = data.databricks_service_principal.github_action.application_id
    privileges = ["EXECUTE"]
  }

  depends_on = [databricks_group.role_analyst]
}
