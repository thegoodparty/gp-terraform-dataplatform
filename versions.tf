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
      version = "~> 5.70"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
