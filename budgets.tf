# Account-level budget alert for Sigma spend (Public Preview resource). Filters on
# the purpose=sigma tag, which propagates into system.billing.usage, rather than on
# the warehouse id, so any future sigma-tagged compute is covered too. POV-scale
# spend ran ~$110/month list price (May-June 2026); the threshold leaves headroom
# for the org rollout while still catching runaway usage.
resource "databricks_budget" "sigma" {
  provider     = databricks.account
  display_name = "sigma-warehouse-monthly"

  alert_configurations {
    time_period        = "MONTH"
    trigger_type       = "CUMULATIVE_SPENDING_EXCEEDED"
    quantity_type      = "LIST_PRICE_DOLLARS_USD"
    quantity_threshold = "400"

    action_configurations {
      action_type = "EMAIL_NOTIFICATION"
      target      = "sanjay@goodparty.org"
    }
  }

  filter {
    tags {
      key = "purpose"
      value {
        operator = "IN"
        values   = ["sigma"]
      }
    }
  }
}
