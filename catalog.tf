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
