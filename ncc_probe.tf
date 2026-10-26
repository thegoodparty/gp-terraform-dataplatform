# Throwaway: reads the account's NCCs so the PR plan shows whether one exists.
# Removed before review.
data "databricks_mws_network_connectivity_configs" "probe_all" {
  provider = databricks.account
}

data "databricks_mws_network_connectivity_configs" "probe_us_west_2" {
  provider = databricks.account
  region   = "us-west-2"
}

data "databricks_mws_network_connectivity_config" "probe" {
  for_each = toset(data.databricks_mws_network_connectivity_configs.probe_all.names)
  provider = databricks.account
  name     = each.value
}

output "ncc_probe_names_all" {
  value = data.databricks_mws_network_connectivity_configs.probe_all.names
}

output "ncc_probe_names_us_west_2" {
  value = data.databricks_mws_network_connectivity_configs.probe_us_west_2.names
}

output "ncc_probe_details" {
  value = {
    for name, ncc in data.databricks_mws_network_connectivity_config.probe : name => {
      id     = ncc.network_connectivity_config_id
      region = ncc.region
      egress = ncc.egress_config
    }
  }
}
