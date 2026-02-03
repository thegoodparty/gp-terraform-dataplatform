terraform {
  required_version = "~> 1.14.3"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.50"
    }
    astro = {
      source  = "astronomer/astro"
      version = "~> 1.0"
    }
  }
}
