# Good Party Data Platform

Terraform configuration for managing the Good Party data infrastructure:
- **Databricks Unity Catalog** - Mart schemas and access control
- **Astronomer (Astro)** - Airflow deployments for orchestration

## Quick Start

### Prerequisites

- Terraform ~> 1.14.3 (`brew install hashicorp/tap/terraform`)
- Astro CLI (`brew install astronomer/tap/astro`)
- Databricks CLI with `DEFAULT` and `ACCOUNT` profiles configured

### Setup

1. Copy configuration files:
   ```bash
   cp .env.example .env
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Fill in your values in both files

3. Load environment variables:
   ```bash
   source .env
   ```

4. Initialize Terraform:
   ```bash
   terraform init
   ```

5. Import existing resources (first time only):
   ```bash
   # Databricks catalog
   terraform import databricks_catalog.main goodparty_data_catalog

   # Astro workspace
   terraform import astro_workspace.data_engineering <workspace-id>
   ```

6. Apply:
   ```bash
   terraform plan
   terraform apply
   ```

---

## Databricks Unity Catalog

### What It Manages

- Catalog: `goodparty_data_catalog`
- Mart schemas with automatic reader groups and permissions
- Service principal access (dbt Cloud, Airbyte, etc.)

### Adding a New Mart

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

---

## Astronomer (Astro) Airflow

### Deployment Strategy

| Environment | Management | Trigger |
|-------------|------------|---------|
| **dev** | Local Terraform | Manual `terraform apply` |
| **prod** | GitHub Actions | Merge to `main` branch |

### Dev Deployment

The dev deployment is managed locally and includes:
- Development mode enabled
- Hibernation schedule (overnight)
- A5 workers (0-10, scale to zero)
- SMALL scheduler

### Prod Deployment

The prod deployment is created automatically via GitHub Actions when merging to `main`.

**Configuration:** See `config/prod.tfvars`

**Cost optimization:**
- SMALL scheduler
- A5 workers (smallest type)
- Scale to zero when idle
- No high availability (can enable later)

### GitHub Actions Setup

Add these secrets to your GitHub repository:

| Secret | Description |
|--------|-------------|
| `ASTRO_API_TOKEN` | Astronomer API token |
| `ASTRO_ORGANIZATION_ID` | Astronomer org ID |
| `DATABRICKS_ACCOUNT_ID` | Databricks account ID |
| `DATABRICKS_WORKSPACE_ID` | Databricks workspace ID |

The workflow triggers on:
- Push to `main` (auto-apply)
- Manual dispatch (plan or apply)

---

## File Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy-prod.yml    # GitHub Actions for prod deployment
├── config/
│   ├── marts.yaml             # Mart definitions
│   └── prod.tfvars            # Production Astro configuration
├── astro.tf                   # Astro workspace and deployments
├── catalog.tf                 # Databricks catalog
├── groups.tf                  # Databricks groups
├── locals.tf                  # Local values
├── outputs.tf                 # Terraform outputs
├── permissions.tf             # Databricks grants
├── provider.tf                # Provider configuration
├── schemas.tf                 # Databricks schemas
├── variables.tf               # Input variables
├── versions.tf                # Terraform and provider versions
├── .env.example               # Environment variables template
└── terraform.tfvars.example   # Terraform variables template
```

## Requirements

| Provider | Version |
|----------|---------|
| Terraform | ~> 1.14.3 |
| databricks/databricks | ~> 1.50 |
| astronomer/astro | ~> 1.0 |
