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
    # One time_sleep in bifrost_usage_storage.tf: IAM policy changes are eventually
    # consistent, so the external location can fail on a call seconds after the write.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
