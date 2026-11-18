resource "databricks_catalog" "main" {
  name           = "goodparty_data_catalog"
  comment        = "Main data catalog for Good Party"
  isolation_mode = "OPEN"

  properties = {
    managed_by = "terraform"
  }

  lifecycle {
    prevent_destroy = true
    # Ignore all changes to preserve existing production catalog configuration
    ignore_changes = all
  }
}

# Everything a loader writes, and nothing dbt builds. Held apart from the prod
# catalog because analyst holds SELECT on the whole of prod and Unity Catalog has
# no DENY, so a raw schema inside it would be readable by every masked reader.
# Raw tables carry tags, but no policy attaches to them yet: the masking
# functions live in the prod catalog's governance schema, and a policy's function
# has to resolve in the catalog the policy is on. So raw is held by its grants
# alone today, and a view over raw would carry no mask from the table beneath it.
# README says what closing that needs.
resource "databricks_catalog" "raw" {
  name           = "raw"
  comment        = "Loader output (Airbyte, the L2 loads, pipeline sources). Read in the clear only by the roles that must."
  isolation_mode = "OPEN"
  storage_root   = "${var.catalog_storage_bucket}/raw"

  properties = {
    managed_by = "terraform"
  }

  depends_on = [
    databricks_grants.external_location_storage
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Personal and CI work. Its own catalog so a dev build cannot land its staging and
# intermediate layers, sensitive columns included, next to prod, and so the
# schemas dbt creates per user and per pull request stop accumulating in prod.
resource "databricks_catalog" "dev" {
  name           = "dev"
  comment        = "Personal dev schemas and CI builds. Built under the reader roles, so values arrive masked."
  isolation_mode = "OPEN"
  storage_root   = "${var.catalog_storage_bucket}/dev"

  properties = {
    managed_by = "terraform"
  }

  depends_on = [
    databricks_grants.external_location_storage
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_catalog" "segment_storage" {
  name           = "segment_storage"
  comment        = "Dedicated catalog for Segment storage destination"
  isolation_mode = "OPEN"
  storage_root   = "${var.catalog_storage_bucket}/segment_storage"

  properties = {
    managed_by = "terraform"
  }

  depends_on = [
    databricks_grants.external_location_storage
  ]

  lifecycle {
    prevent_destroy = true
  }
}
