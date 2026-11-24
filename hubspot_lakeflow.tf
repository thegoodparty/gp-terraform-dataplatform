# =============================================================================
# HubSpot ingestion (Lakeflow Connect)
# =============================================================================
# The `hubspot_lakeflow` connection was made in the UI, because the connector
# authenticates with an OAuth app and the sign-in is a person's, so Terraform
# grants on the connection rather than managing it.
#
# Databricks requires USE_CONNECTION of the principal a pipeline runs as. The
# HubSpot pipeline runs as the ingestor role, so without this it fails on its
# first update with "Failed to retrieve connection from the unity catalog".
#
# Singular grant because databricks_grants rejects privileges on a connection:
# databricks/terraform-provider-databricks#5398.
#
# The landing schema is deliberately not here. ingestor holds CREATE_SCHEMA on
# raw, so whoever sets up the pipeline creates `raw.hubspot` and hands it to the
# role; the README says how. A schema resource here would make every new source
# a Terraform change, which is the arrangement that decision replaced.
resource "databricks_grant" "hubspot_lakeflow_connection" {
  foreign_connection = "hubspot_lakeflow"
  principal          = databricks_group.role_ingestor.display_name
  privileges         = ["USE_CONNECTION"]
}
