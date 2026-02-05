# Good Party Data Platform

Terraform configuration for managing the Good Party data infrastructure:
- **Databricks Unity Catalog** - Mart schemas and access control
- **Astronomer (Astro)** - Airflow deployments for orchestration

## Quick Start

### Prerequisites

- Terraform ~> 1.14.4 (`brew install hashicorp/tap/terraform`)
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

CI runs `terraform plan` on every push/PR to `main`. Apply is always manual to avoid accidental infrastructure changes.

| Environment | Config File | Description |
|-------------|-------------|-------------|
| **dev** | `config/dev.tfvars` | Development only |
| **prod** | `config/prod.tfvars` | Production only |

### Environment Configuration

**Dev** (`config/dev.tfvars`):
- Development mode enabled (reduced costs)
- Hibernation schedule (sleeps overnight on weekdays)
- Kubernetes executor
- SMALL scheduler

**Prod** (`config/prod.tfvars`):
- Production mode (always on)
- No hibernation
- Kubernetes executor
- SMALL scheduler

### Applying Changes

After reviewing the plan in CI, apply changes manually:

```bash
source .env
terraform apply -var-file=config/dev.tfvars -var-file=config/prod.tfvars
```

> **Note:** Both var files must be provided together. The deployments have `prevent_destroy = true`, so applying with only one var file would fail when trying to "destroy" the omitted environment.

### Manual Dispatch

To run a plan via GitHub Actions:

1. Go to **Actions** tab in GitHub
2. Select **Terraform CI/CD** workflow
3. Click **Run workflow**
4. Review the plan output (includes both dev and prod)

### GitHub Actions Setup

Add these **secrets** to your GitHub repository:

| Secret | Description |
|--------|-------------|
| `ASTRO_API_TOKEN` | Astronomer API token |
| `DATABRICKS_CLIENT_ID` | Databricks service principal client ID |
| `DATABRICKS_CLIENT_SECRET` | Databricks service principal secret |

Add these **variables** to your GitHub repository:

| Variable | Description |
|----------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for OIDC authentication |
| `AWS_REGION` | AWS region (e.g., `us-west-2`) |
| `ASTRO_ORGANIZATION_ID` | Astronomer organization ID |
| `ASTRO_CONTACT_EMAILS` | Comma-separated alert emails |
| `DATABRICKS_ACCOUNT_ID` | Databricks account ID |
| `DATABRICKS_WORKSPACE_ID` | Databricks workspace ID |
| `DATABRICKS_WORKSPACE_HOST` | Databricks workspace URL |

The workflow triggers on:
- Pull request to `main` (plan only)
- Push to `main` (plan only)
- Manual dispatch (plan only)

---

## File Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform-cicd.yaml    # GitHub Actions CI/CD workflow
├── config/
│   ├── dev.tfvars             # Dev environment config
│   ├── prod.tfvars            # Prod environment config
│   └── marts.yaml             # Mart definitions
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
| Terraform | ~> 1.14.4 |
| databricks/databricks | ~> 1.50 |
| astronomer/astro | ~> 1.0 |
