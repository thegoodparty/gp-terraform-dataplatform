# Dedicated Small serverless warehouse per product agent for compute and cost isolation.
resource "databricks_sql_endpoint" "agent" {
  for_each                  = local.agent_products
  name                      = each.value.warehouse_name
  cluster_size              = "Small"
  enable_serverless_compute = true
  warehouse_type            = "PRO"
  auto_stop_mins            = 10
  max_num_clusters          = 1

  tags {
    custom_tags {
      key   = "product"
      value = each.key
    }
    custom_tags {
      key   = "purpose"
      value = "agent"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
