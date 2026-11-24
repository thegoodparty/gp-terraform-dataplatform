# =============================================================================
# Terraform-Managed Service Principals
# =============================================================================
# Service principals created and fully managed by Terraform.
# Pre-existing SPs (looked up via data sources) remain in groups.tf.

locals {
  airflow_service_principals = {
    airflow     = "airflow"
    airflow_dev = "airflow_dev"
  }
}

resource "databricks_service_principal" "airflow" {
  for_each     = local.airflow_service_principals
  provider     = databricks.account
  display_name = each.value
  lifecycle { prevent_destroy = true }
}

# Assign to workspace so they can access workspace-level resources
resource "databricks_mws_permission_assignment" "airflow" {
  for_each     = local.airflow_service_principals
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.airflow[each.key].id
  permissions  = ["USER"]
}

# dbt Cloud staging service principal for the staging deployment environment
resource "databricks_service_principal" "dbt_cloud_staging" {
  provider     = databricks.account
  display_name = "dbt_cloud_staging"
  lifecycle { prevent_destroy = true }
}

resource "databricks_mws_permission_assignment" "dbt_cloud_staging" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.dbt_cloud_staging.id
  permissions  = ["USER"]
}

resource "databricks_service_principal" "segment_storage" {
  provider     = databricks.account
  display_name = "segment_storage"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "segment_storage" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.segment_storage.id
  permissions  = ["USER"]
}

# Sigma Computing service principal for the BI POV.
# Mart access via group membership in groups.tf;
# dedicated wh-sigma-pov warehouse grant in permissions.tf.
resource "databricks_service_principal" "sigma" {
  provider     = databricks.account
  display_name = "sigma"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "sigma" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.sigma.id
  permissions  = ["USER"]
}

resource "databricks_service_principal" "icp_finder" {
  provider     = databricks.account
  display_name = "icp-finder"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "icp_finder" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.icp_finder.id
  permissions  = ["USER"]
}

# Read-only SP for the analytics governance loop. Authenticates via GitHub OIDC
# federation (below), so there is no client secret to rotate.
resource "databricks_service_principal" "product_analytics" {
  provider     = databricks.account
  display_name = "product_analytics"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "product_analytics" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.product_analytics.id
  permissions  = ["USER"]
}

# Only runs on omni's main branch can authenticate; a job-level `environment:`
# would change the token subject and break this.
resource "databricks_service_principal_federation_policy" "product_analytics_github" {
  provider             = databricks.account
  service_principal_id = tonumber(databricks_service_principal.product_analytics.id)

  oidc_policy = {
    issuer    = "https://token.actions.githubusercontent.com"
    audiences = ["https://github.com/thegoodparty"]
    subject   = "repo:thegoodparty/omni:ref:refs/heads/main"
  }
}

# Win and Serve product agent service principals. OAuth M2M credentials generated manually.
resource "databricks_service_principal" "agent" {
  for_each     = local.agent_products
  provider     = databricks.account
  display_name = each.value.sp_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "agent" {
  for_each     = local.agent_products
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.agent[each.key].id
  permissions  = ["USER"]
}

# The gp-api application's read-only principal for direct SQL against its
# mart. OAuth M2M credentials generated manually; see README.
resource "databricks_service_principal" "gp_api" {
  provider     = databricks.account
  display_name = local.gp_api.sp_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "gp_api" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.gp_api.id
  permissions  = ["USER"]
}

# GitHub OIDC federation for this repo's CI, which runs as the github-action SP
# (data source in groups.tf). One subject per caller: PR plans, Deploy's plan on
# main, and the apply job, which runs in the `production` environment.
locals {
  terraform_ci_oidc_subjects = {
    pull_request = "repo:thegoodparty/gp-terraform-dataplatform:pull_request"
    main         = "repo:thegoodparty/gp-terraform-dataplatform:ref:refs/heads/main"
    production   = "repo:thegoodparty/gp-terraform-dataplatform:environment:production"
  }
}

resource "databricks_service_principal_federation_policy" "github_action_ci" {
  for_each             = local.terraform_ci_oidc_subjects
  provider             = databricks.account
  service_principal_id = tonumber(data.databricks_service_principal.github_action.id)
  description          = "gp-terraform-dataplatform CI: ${each.key}"

  oidc_policy = {
    issuer    = "https://token.actions.githubusercontent.com"
    audiences = ["https://github.com/thegoodparty"]
    subject   = each.value
  }
}

# The principal Databricks ingestion pipelines (Lakeflow Connect) run as, so a
# pipeline writes raw without lending its creator's grants. Its raw grants are in
# permissions.tf. The pipelines are serverless, so no cluster entitlement.
resource "databricks_service_principal" "databricks_ingestor" {
  provider     = databricks.account
  display_name = "databricks_ingestor"

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_mws_permission_assignment" "databricks_ingestor" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.databricks_ingestor.id
  permissions  = ["USER"]
}

# Setting a pipeline's run_as to this principal needs the User role on it. The
# rule set is authoritative, so it keeps the creator's Manager role too; the
# admin group sets pipelines up in the console, and github-action owns this SP.
resource "databricks_access_control_rule_set" "databricks_ingestor" {
  provider = databricks.account
  name     = "accounts/${var.databricks_account_id}/servicePrincipals/${databricks_service_principal.databricks_ingestor.application_id}/ruleSets/default"

  grant_rules {
    principals = [data.databricks_service_principal.github_action.acl_principal_id]
    role       = "roles/servicePrincipal.manager"
  }

  grant_rules {
    principals = [data.databricks_group.admin_group.acl_principal_id]
    role       = "roles/servicePrincipal.user"
  }
}

# Databricks requires USE_CONNECTION of the principal a pipeline runs as.
# Singular because databricks_grants rejects USE_CONNECTION on a connection.
resource "databricks_grant" "databricks_ingestor_amplitude_connection" {
  foreign_connection = "amplitude-goodparty-org"
  principal          = databricks_service_principal.databricks_ingestor.application_id
  privileges         = ["USE_CONNECTION"]
}
