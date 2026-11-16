terraform {
  required_version = "~> 1.14.4"

  backend "s3" {
    bucket       = "goodparty-terraform-state-us-west-2"
    key          = "dataplatform/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.50"
    }
    astro = {
      source  = "astronomer/astro"
      version = "~> 1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # For one resource: a short sleep between writing an IAM role policy and
    # creating the external location that exercises it. IAM changes are
    # eventually consistent, so without it the first apply can fail intermittently
    # on a call made seconds after the policy write. Only `bifrost_usage_storage.tf`
    # uses it.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
