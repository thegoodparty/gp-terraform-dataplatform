# Databricks workspace-level provider (for catalogs, schemas, workspace resources)
# Uses CLI profile locally, or DATABRICKS_CLIENT_ID/DATABRICKS_CLIENT_SECRET env vars in CI
provider "databricks" {
  profile = var.databricks_workspace_profile
  host    = var.databricks_workspace_host
}

# Databricks account-level provider (for account groups, service principals)
# Uses CLI profile locally, or DATABRICKS_CLIENT_ID/DATABRICKS_CLIENT_SECRET env vars in CI
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
  profile    = var.databricks_account_profile
}

# Astronomer provider for Astro Airflow deployments
# Token should be set via ASTRO_API_TOKEN environment variable
provider "astro" {
  organization_id = var.astro_organization_id
}

# AWS provider for the people-api loader's S3 storage + IAM.
# Credentials come from the standard AWS chain (CI role / local profile).
# Project is tagged per-resource (local.loader_tags); default_tags is reserved for
# repo-wide tags so future unrelated AWS resources don't inherit a loader Project.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
    }
  }
}
