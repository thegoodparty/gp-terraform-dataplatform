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

### CI/CD Flows

| Trigger | What happens |
|---------|--------------|
| **Pull Request** | Run plan, post results as PR comment |
| **Merge to main** | Run plan again to confirm main is in a good state |
| **Manual dispatch** | Run plan, then apply (if `dry_run` unchecked) |

Both dev and prod Airflow environments are defined in `locals.tf` and always deploy together.

### Environment Configuration

**Dev** (astro-dev):
- Development mode enabled (reduced costs)
- Hibernation schedule (sleeps overnight on weekdays)
- Kubernetes executor
- SMALL scheduler

**Prod** (astro-prod):
- Production mode (always on)
- No hibernation
- Kubernetes executor
- SMALL scheduler

### Deploying Changes

1. **Merge PR** to `main` after reviewing the plan in PR comments
2. **Trigger apply** manually:

   **Via GitHub UI:**
   - Go to **Actions** → **Deploy** → **Run workflow**
   - Uncheck **"Dry run (plan only, no apply)"**
   - Click **Run workflow**

   **Via CLI:**
   ```bash
   gh workflow run deploy.yaml -f dry_run=false
   ```

### Local Development

For local testing or emergency fixes:

```bash
source .env
terraform plan
terraform apply
```

### GitHub Actions Setup

#### 1. Create the `production` Environment (optional)

1. Go to **Settings** > **Environments** > **New environment**
2. Name it `production`
3. Under **Deployment branches and tags**:
   - Select **Selected branches and tags**
   - Add branch: `main`

> **Note:** If you have GitHub Team/Enterprise, you can enable **Required reviewers** under Deployment protection rules for an additional approval gate.

#### 2. Add Secrets

| Secret | Description |
|--------|-------------|
| `ASTRO_API_TOKEN` | Astronomer API token |
| `DATABRICKS_CLIENT_ID` | Databricks service principal client ID |
| `DATABRICKS_CLIENT_SECRET` | Databricks service principal secret |

#### 3. Add Variables

| Variable | Description |
|----------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for OIDC authentication |
| `AWS_REGION` | AWS region (e.g., `us-west-2`) |
| `ASTRO_ORGANIZATION_ID` | Astronomer organization ID |
| `ASTRO_CONTACT_EMAILS` | Comma-separated alert emails |
| `DATABRICKS_ACCOUNT_ID` | Databricks account ID |
| `DATABRICKS_WORKSPACE_ID` | Databricks workspace ID |
| `DATABRICKS_WORKSPACE_HOST` | Databricks workspace URL |

### Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `on-pull-request.yaml` | Pull request | Plan + PR comment |
| `deploy.yaml` | Push to main | Plan only (validate main) |
| `deploy.yaml` | Manual dispatch | Plan + Apply (if `dry_run` unchecked) |

Reusable workflows (`tf-plan.yaml`, `tf-apply.yaml`) are called by the above.

---

## File Structure

```
.
├── .github/
│   └── workflows/
│       ├── tf-plan.yaml           # Reusable: Terraform plan
│       ├── tf-apply.yaml          # Reusable: Terraform apply (production)
│       ├── on-pull-request.yaml   # PR workflow: plan + comment
│       └── deploy.yaml            # Deploy workflow: plan + apply
├── config/
│   └── marts.yaml             # Mart definitions
├── astro.tf                   # Astro workspace and deployments
├── catalog.tf                 # Databricks catalog
├── groups.tf                  # Databricks groups
├── locals.tf                  # Local values + Astro environment configs
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
