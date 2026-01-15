resource "databricks_catalog" "main" {
  name           = "goodparty_data_catalog"
  comment        = "Main data catalog for Good Party"
  isolation_mode = "OPEN"

  properties = {
    managed_by = "terraform"
  }

  lifecycle {
    prevent_destroy = true
    # Ignore changes to preserve existing catalog configuration
    ignore_changes = [storage_root, comment, properties]
  }
}
