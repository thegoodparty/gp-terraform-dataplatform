# Good Party Databricks Data Platform

Minimal Terraform configuration for managing Unity Catalog mart schemas.

## What This Does

Creates new mart schemas in `goodparty_data_catalog` with automatic:
- Schema creation
- Reader groups (account-level)
- Permissions (read for groups, write for dbt_cloud)

## Adding a New Mart

Edit `config/marts.yaml`:
```yaml
marts:
  - name: newmart
    description: "Your mart description"
```

Run:
```bash
terraform plan
terraform apply
```

This creates:
- Schema: `goodparty_data_catalog.mart_newmart`
- Group: `mart_newmart_readers`
- Grants: USE_SCHEMA, SELECT for readers; CREATE_TABLE, MODIFY for dbt_cloud

## Setup

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in values
2. `terraform init`
3. `terraform import databricks_catalog.main goodparty_data_catalog` (first time only)
4. `terraform apply`

## Requirements

- Databricks CLI with `DEFAULT` and `ACCOUNT` profiles configured
- Terraform ~> 1.14.3
