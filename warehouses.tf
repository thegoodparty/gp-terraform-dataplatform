# Dedicated Small serverless warehouse per product agent for compute and cost isolation.
resource "databricks_sql_endpoint" "agent" {
  for_each                  = local.agent_products
  name                      = each.value.warehouse_name
  cluster_size              = "Small"
  enable_serverless_compute = true
  warehouse_type            = "PRO" # required for serverless warehouses; there is no SERVERLESS type
  auto_stop_mins            = 5
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

# Dedicated serverless warehouse for the Sigma BI connection, shared by all Sigma
# users (single-connection model). Created in the UI for the May POV and adopted
# into Terraform via the import block below. The live Sigma connection pins this
# warehouse's id in its HTTP path, so it must never be destroyed or replaced.
import {
  to = databricks_sql_endpoint.sigma
  id = "7caad5bfd074c2fa"
}

resource "databricks_sql_endpoint" "sigma" {
  name                      = "wh-sigma-pov"
  cluster_size              = "2X-Small"
  enable_serverless_compute = true
  warehouse_type            = "PRO"
  auto_stop_mins            = 10
  min_num_clusters          = 1
  max_num_clusters          = 3

  tags {
    custom_tags {
      key   = "purpose"
      value = "sigma"
    }
    custom_tags {
      key   = "team"
      value = "data-platform"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Dedicated serverless warehouse for the gp-api application's direct queries,
# keeping app-serving traffic off the shared analytics and agent compute.
#
# Sized to scale OUT, not up: gp-api's voter reads are many small queries -- one
# saved-list page fans out to roughly forty -- so the constraint is how many run
# at once rather than how fast one runs. X-Small and Medium measured within 2%
# of each other on warm single-query latency, while p95 across 25 concurrent
# reads went 9.5s to 4.3s. So keep the cluster small and let it add clusters.
resource "databricks_sql_endpoint" "gp_api" {
  name                      = local.gp_api.warehouse_name
  cluster_size              = "X-Small"
  enable_serverless_compute = true
  warehouse_type            = "PRO" # required for serverless warehouses; there is no SERVERLESS type
  auto_stop_mins            = 2
  max_num_clusters          = 4

  tags {
    custom_tags {
      key   = "product"
      value = "gp_api"
    }
    custom_tags {
      key   = "purpose"
      value = "app_serving"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
