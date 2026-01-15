# Databricks Unity Catalog Terraform Project - Status
---

## Current State

### Infrastructure Overview

This repository manages a complete Databricks Unity Catalog setup on AWS with:

- **1 Catalog**: `goodparty_data_catalog_dev`
- **3 Core Schemas**: `raw`, `dbt`, and dynamic `mart_*` schemas (configured via YAML)
- **5 Account-Level Groups**: With environment-specific naming (`-dev` suffix)
- **Complete Permissions**: Unity Catalog grants for all groups across all schemas

### Architecture Summary

```
goodparty_data_catalog_dev/
├── raw/                    # Ingested data (bronze layer)
├── dbt/                    # Transformed data (silver layer)
├── mart_civics/           # Gold layer - civics analytics
└── mart_research/         # Gold layer - research reporting
```

### Groups & Permissions

| Group | Catalog | Raw Schema | DBT Schema | Marts | Purpose |
|-------|---------|------------|------------|-------|---------|
| `ingester-dev` | USE_CATALOG | USE_SCHEMA<br>CREATE_TABLE<br>MODIFY | - | - | Data ingestion pipeline |
| `transformer-dev` | USE_CATALOG | USE_SCHEMA<br>SELECT | USE_SCHEMA<br>CREATE_TABLE<br>MODIFY | - | Production dbt runs |
| `dbt-developers-dev` | USE_CATALOG<br>CREATE_SCHEMA | USE_SCHEMA<br>SELECT | USE_SCHEMA<br>SELECT | USE_SCHEMA<br>SELECT (all) | Day-to-day dbt development |
| `mart_civics_readers-dev` | USE_CATALOG | - | - | USE_SCHEMA<br>SELECT (civics only) | Read civics mart |
| `mart_research_readers-dev` | USE_CATALOG | - | - | USE_SCHEMA<br>SELECT (research only) | Read research mart |

### AWS Infrastructure

- **S3 Bucket**: `goodparty-warehouse-databricks-dev`
  - Versioning enabled
  - AES256 encryption
  - Public access blocked
- **IAM Role**: `databricks-default-storage-dev`
  - Trust policy with external ID for Databricks access
  - S3 read/write/list permissions
- **Storage Credential**: `goodparty_dev`
- **External Location**: `goodparty_dev_location` → `s3://goodparty-warehouse-databricks-dev/goodparty_data_catalog_dev`

### Configuration Files

**Core Terraform Files:**
- `versions.tf` - Provider versions (Terraform 1.14.3, Databricks 1.50, AWS 5.0)
- `provider.tf` - Dual Databricks providers (workspace + account) + AWS provider
- `variables.tf` - All input variables (account_id, environment, profiles)
- `terraform.tfvars` - Actual values (gitignored, see terraform.tfvars.example)
- `locals.tf` - Computed values, YAML parsing, workspace_id
- `data.tf` - Data sources (current_user, aws_caller_identity)
- `outputs.tf` - Outputs for all resource IDs

**Resource Files:**
- `aws.tf` - S3 bucket, IAM role, IAM policy
- `storage_credential.tf` - Databricks storage credential
- `external_location.tf` - External location mapping
- `catalog.tf` - Unity Catalog definition
- `schemas.tf` - Raw, dbt, and dynamic mart schemas
- `account_groups.tf` - Account-level groups and workspace assignments
- `permissions.tf` - All Unity Catalog grants

**Configuration:**
- `config/marts.yaml` - Mart definitions (external, version-controlled)

### Databricks Authentication

**Workspace-Level** (DEFAULT profile):
```ini
[DEFAULT]
host      = https://dbc-3d8ca484-79f3.cloud.databricks.com
auth_type = databricks-cli
```

**Account-Level** (ACCOUNT profile):
```ini
[ACCOUNT]
host      = https://accounts.cloud.databricks.com
account_id = 4c2ba7ae-dc6f-48c3-9eaa-fd09d11c3b40
auth_type = databricks-cli
```

### Current Variables

From `terraform.tfvars`:
```hcl
databricks_account_id        = "4c2ba7ae-dc6f-48c3-9eaa-fd09d11c3b40"
environment                  = "dev"
aws_profile                  = "gp-engineer"
databricks_workspace_profile = "DEFAULT"
databricks_account_profile   = "ACCOUNT"
```

Workspace ID: `3578414625112071`

---

## Completed Tasks

✅ **Phase 1: Foundation** (Steps 1-8)
- [x] Initialize Git repository with .gitignore
- [x] Create Terraform provider configuration (workspace + account providers)
- [x] Add workspace data source validation
- [x] Add AWS provider configuration
- [x] Create dev S3 bucket with versioning/encryption
- [x] Create IAM role and policy for storage credential
- [x] Create Databricks storage credential
- [x] Create catalog with storage location

✅ **Phase 2: Core Schemas** (Steps 9-13)
- [x] Create raw schema
- [x] Add dbt schema
- [x] Create mart configuration YAML (civics, research)
- [x] Read mart YAML in Terraform locals
- [x] Create dynamic mart schemas from YAML

✅ **Phase 3: Account-Level Groups** (Steps 14-17)
- [x] Configure account-level Databricks provider with ACCOUNT profile
- [x] Authenticate with `databricks auth login --profile ACCOUNT`
- [x] Create account-level groups with environment suffix
- [x] Assign account groups to workspace via mws_permission_assignment

✅ **Phase 4: Permissions** (Steps 18-21)
- [x] Grant catalog USE_CATALOG to all groups
- [x] Grant dbt-developers CREATE_SCHEMA on catalog
- [x] Grant raw schema permissions (ingester write, transformer + dbt-developers read)
- [x] Grant dbt schema permissions (transformer write, dbt-developers read)
- [x] Grant mart permissions (specific readers + dbt-developers read all)

✅ **Phase 5: Variables & Parameterization** (Steps 22-23)
- [x] Extract environment to variable with validation
- [x] Add AWS and Databricks profile variables
- [x] Create terraform.tfvars and terraform.tfvars.example

✅ **Phase 6: Additional Groups**
- [x] Add dbt-developers group with read-all + CREATE_SCHEMA permissions

---

## Known Issues / TODOs

### Critical Issues (Blocking Production)

1. **IAM Validation Workaround** (external_location.tf:15)
   - Currently using `skip_validation = true`
   - Issue: External location validation fails with IAM permission error
   - Impact: May indicate underlying IAM propagation delay or policy issue
   - Action Required: Investigate and remove skip_validation once resolved
   - File: `external_location.tf`

### Enhancement TODOs

1. **Workspace Object Management**
   - Currently using hardcoded workspace_id in locals.tf
   - Future: Manage workspace as Terraform resource
   - File: `locals.tf:4` (TODO comment added)

2. **Service Principal Authentication**
   - Currently using personal admin credentials (dan@goodparty.org)
   - Future: Migrate to service principal for CI/CD
   - Priority: Before production deployment

---

## Pending Implementation Tasks

### Phase 7: Documentation (Step 24)
**Status**: Not Started
**Priority**: High

- [ ] Update README.md with:
  - Architecture overview diagram
  - Prerequisites (Terraform version, AWS CLI, Databricks CLI)
  - Initial setup instructions
  - How to add new marts to config/marts.yaml
  - How to add new groups
  - How to authenticate (workspace vs account profiles)
  - Testing procedures
  - Troubleshooting guide

### Phase 8: Validation (Step 25)
**Status**: Not Started
**Priority**: Medium

Create `scripts/validate_permissions.sh` to verify:
- [ ] Catalog exists via `terraform output`
- [ ] Schemas exist via `databricks unity-catalog schemas list`
- [ ] Groups exist via `databricks groups list`
- [ ] Permissions via `databricks unity-catalog grants get-effective`

Example structure:
```bash
#!/bin/bash
# Validate Unity Catalog setup
set -e

echo "Checking catalog..."
terraform output catalog_name

echo "Checking schemas..."
databricks unity-catalog schemas list --catalog-name goodparty_data_catalog_dev

echo "Checking groups..."
databricks groups list --profile ACCOUNT | grep -E "(ingester|transformer|dbt|mart)"

echo "Checking catalog permissions..."
databricks unity-catalog grants get-effective catalog goodparty_data_catalog_dev

echo "✅ Validation complete"
```

### Phase 9: Remote State (Steps 26-28)
**Status**: Not Started
**Priority**: High (before team collaboration)

**Step 26: Create S3 Backend Bucket**
```bash
aws s3 mb s3://goodparty-dataplatform-terraform-state \
  --profile gp-engineer --region us-east-1

aws s3api put-bucket-versioning \
  --bucket goodparty-dataplatform-terraform-state \
  --versioning-configuration Status=Enabled \
  --profile gp-engineer

aws s3api put-bucket-encryption \
  --bucket goodparty-dataplatform-terraform-state \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --profile gp-engineer
```

**Step 27: Configure S3 Backend**

Update `versions.tf` to add:
```hcl
terraform {
  required_version = "~> 1.14.3"

  backend "s3" {
    bucket  = "goodparty-dataplatform-terraform-state"
    key     = "databricks/unity-catalog/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "gp-engineer"

    # Native S3 state locking (Terraform 1.10+, no DynamoDB needed)
    use_lockfile = true
  }

  required_providers {
    # ... existing providers
  }
}
```

Then migrate:
```bash
terraform init -migrate-state
```

**Step 28: Test State Locking**

Open two terminals:
- Terminal 1: `terraform plan`
- Terminal 2: `terraform plan` (should show lock error)

### Phase 10: Multi-Environment Support (Steps 29-30)
**Status**: Not Started
**Priority**: Medium (needed for stage/prod)

**Step 29: Multiple Raw Schemas Support**

Currently: Single `raw` schema
Future: Support `raw_{source}` pattern for multiple data sources

Add to `config/sources.yaml`:
```yaml
sources:
  - name: salesforce
    description: "Salesforce CRM data"
  - name: stripe
    description: "Stripe payment data"
  - name: segment
    description: "Segment analytics events"
```

Update `schemas.tf`:
```hcl
resource "databricks_schema" "raw_sources" {
  for_each = local.sources_map

  catalog_name = databricks_catalog.main.name
  name         = "raw_${each.key}"
  comment      = each.value.description

  properties = {
    managed_by = "terraform"
    purpose    = "ingestion"
    source     = each.key
  }
}
```

**Step 30: Environment Configuration Templates**

Create `environments/` directory:
```
environments/
├── dev.tfvars
├── stage.tfvars
└── prod.tfvars
```

Example `environments/stage.tfvars`:
```hcl
databricks_account_id        = "4c2ba7ae-dc6f-48c3-9eaa-fd09d11c3b40"
environment                  = "stage"
aws_profile                  = "gp-engineer"
databricks_workspace_profile = "STAGE"
databricks_account_profile   = "ACCOUNT"
```

Usage:
```bash
terraform plan -var-file=environments/stage.tfvars
terraform apply -var-file=environments/stage.tfvars
```

---

## Production Deployment Plan

### Prerequisites
- [ ] Resolve IAM validation issue (remove skip_validation)
- [ ] Create service principal for Terraform
- [ ] Configure S3 remote state
- [ ] Complete documentation
- [ ] Test all permissions with actual service accounts

### Import Existing Production Resources

Once dev is stable, import existing prod resources:

```bash
# Import existing prod catalog
terraform import databricks_catalog.main goodparty_data_catalog

# Import existing prod schemas
terraform import 'databricks_schema.raw' 'goodparty_data_catalog.raw'
terraform import 'databricks_schema.dbt' 'goodparty_data_catalog.dbt'

# Import existing prod groups (if account-level)
terraform import 'databricks_group.ingester_account' <group-id>

# Import existing AWS resources
terraform import aws_s3_bucket.unity_catalog_prod goodparty-warehouse-databricks
terraform import aws_iam_role.databricks_storage_prod <role-name>
```

### Multi-Environment Strategy

1. **Dev Environment** (current)
   - Catalog: `goodparty_data_catalog_dev`
   - Groups: `*-dev` suffix
   - S3: `goodparty-warehouse-databricks-dev`
   - Purpose: Development and testing

2. **Stage Environment** (future)
   - Catalog: `goodparty_data_catalog_stage`
   - Groups: `*-stage` suffix
   - S3: `goodparty-warehouse-databricks-stage`
   - Purpose: Pre-production validation

3. **Production Environment** (import existing)
   - Catalog: `goodparty_data_catalog` (no suffix)
   - Groups: No suffix (e.g., `ingester`, `transformer`)
   - S3: `goodparty-warehouse-databricks`
   - Purpose: Production workloads

---

## How to Resume Work

### 1. Verify Current State
```bash
cd /Users/danball/projects/gp-terraform-dataplatform

# Check Terraform state
terraform state list

# Verify authentication
databricks auth login --profile DEFAULT
databricks auth login --profile ACCOUNT

# Check AWS credentials
aws sts get-caller-identity --profile gp-engineer
```

### 2. Choose Next Task

Pick from pending tasks above based on priority:
- **High Priority**: Documentation, Remote State, IAM validation fix
- **Medium Priority**: Validation script, Multi-environment support
- **Future**: Multiple raw schemas, Service principal migration

### 3. Make Changes

Follow the implementation patterns established:
- Account-level resources use `provider = databricks.account`
- All groups have environment suffix: `${var.environment}`
- Permissions use combined `databricks_grants` resources per securable
- YAML-driven configuration for extensible resources (marts, sources)

### 4. Test Changes
```bash
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

## Quick Reference Commands

### Terraform Operations
```bash
# Plan changes
terraform plan

# Apply with auto-approve
terraform apply -auto-approve

# Show specific resource
terraform state show databricks_catalog.main

# List all resources
terraform state list

# Output values
terraform output
```

### Databricks CLI
```bash
# List catalogs
databricks unity-catalog catalogs list

# List schemas in catalog
databricks unity-catalog schemas list \
  --catalog-name goodparty_data_catalog_dev

# List groups (workspace)
databricks groups list --profile DEFAULT

# List groups (account)
databricks groups list --profile ACCOUNT

# Check permissions
databricks unity-catalog grants get-effective \
  catalog goodparty_data_catalog_dev
```

### AWS CLI
```bash
# List S3 buckets
aws s3 ls --profile gp-engineer

# Check IAM role
aws iam get-role \
  --role-name databricks-default-storage-dev \
  --profile gp-engineer
```

---

## File Structure Summary

```
.
├── .gitignore                      # Terraform and sensitive files
├── .gitattributes                  # Git line ending settings
├── README.md                       # User-facing documentation (needs update)
├── PROJECT_STATUS.md              # This file - current state and plan
├── versions.tf                     # Terraform and provider versions
├── provider.tf                     # Provider configurations
├── variables.tf                    # Input variable definitions
├── terraform.tfvars               # Actual values (gitignored)
├── terraform.tfvars.example       # Template for tfvars
├── locals.tf                       # Local computed values
├── data.tf                         # Data sources
├── outputs.tf                      # Output definitions
├── aws.tf                          # AWS infrastructure (S3, IAM)
├── storage_credential.tf          # Databricks storage credential
├── external_location.tf           # External location mapping
├── catalog.tf                      # Unity Catalog
├── schemas.tf                      # All schemas (raw, dbt, marts)
├── account_groups.tf              # Account-level groups
├── permissions.tf                  # Unity Catalog grants
└── config/
    └── marts.yaml                  # Mart configuration
```

---

## Contact & Resources

- **Project Lead**: dan@goodparty.org
- **Databricks Workspace**: https://dbc-3d8ca484-79f3.cloud.databricks.com
- **Databricks Account**: https://accounts.cloud.databricks.com
- **AWS Account**: 333022194791

**Documentation Links**:
- [Databricks Unity Catalog Docs](https://docs.databricks.com/en/data-governance/unity-catalog/)
- [Terraform Databricks Provider](https://registry.terraform.io/providers/databricks/databricks/latest/docs)
- [S3 Native State Locking](https://developer.hashicorp.com/terraform/language/backend/s3)
