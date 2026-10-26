# Throwaway: reads the account's NCCs so the PR plan shows whether one exists.
# Removed before review.
data "databricks_mws_network_connectivity_configs" "probe_all" {
  provider = databricks.account
}

data "databricks_mws_network_connectivity_configs" "probe_us_west_2" {
  provider = databricks.account
  region   = "us-west-2"
}

output "ncc_probe" {
  value = {
    all_count       = try(length(data.databricks_mws_network_connectivity_configs.probe_all.names), 0)
    all_names       = jsonencode(data.databricks_mws_network_connectivity_configs.probe_all.names)
    us_west_2_count = try(length(data.databricks_mws_network_connectivity_configs.probe_us_west_2.names), 0)
    us_west_2_names = jsonencode(data.databricks_mws_network_connectivity_configs.probe_us_west_2.names)
  }
}
