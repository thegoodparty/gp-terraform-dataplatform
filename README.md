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

### Service principal: `product_analytics`

Read-only SP for the analytics governance loop (`omni`'s
`.github/workflows/analytics-governance.yml`). Terraform manages the principal,
its grants, and a GitHub OIDC federation policy, so the workflow authenticates
with a short-lived GitHub token and no client secret exists.

The policy trusts `repo:thegoodparty/omni:ref:refs/heads/main` with audience
`https://github.com/thegoodparty`. Adding a job-level `environment:` to that
workflow changes the token subject and breaks auth until the policy is updated.

### gp-api Postgres mirror (Lakeflow Connect)

`gp_api_mirror.tf` keeps a copy of gp-api's Aurora database (`gpdb`, schema
`public`) in Databricks, a few minutes behind. The Aurora side and the full
runbook live in omni, under `packages/gp-api/deploy/databricks/lakeflow/`.

| Env  | Mirror schema                              | Readers group               |
| ---- | ------------------------------------------ | --------------------------- |
| dev  | `goodparty_data_catalog.gp_api_mirror_dev` | `gp_api_mirror_dev_readers` |
| prod | `goodparty_data_catalog.gp_api_mirror`     | `gp_api_mirror_readers`     |

The mirror holds users' personal data. The readers groups start empty and are
not nested into `data users`; add members in the console, one principal at a
time.

Terraform manages the `sp_gp_api_mirror` service principal (with cluster
creation, for the classic-compute gateway, and a rule set giving `github-action`
the Service Principal User role so CI can set it as `run_as`), both schemas and
their grants, the `gp-api-lakeflow-<env>` secret scopes, and, per env, the
`gp-api-mirror-<env>-gateway` and `gp-api-mirror-<env>-ingestion`
pipelines and the `gp-api-mirror-<env>-ingestion-loop` job. Failure emails go
to the data platform's existing alert list (`ASTRO_CONTACT_EMAILS`); give the
mirror its own list later if that gets noisy.

Stays outside Terraform, because each would put a credential in state or lives
in Postgres:

- the `postgres-password` value in each secret scope
- the Unity Catalog connections `gp_api_dev_lakeflow` and
  `gp_api_prod_lakeflow` (omni's `create-connection.sh`)
- the `databricks_lakeflow` Aurora role's password
- the `databricks_lakeflow` replication slot

Order, per env, dev first:

1. **Apply #1** (this repo, no change needed): the service principal, schemas,
   readers groups, grants and secret scopes.
2. **omni runbook**: once logical replication is on, put the password in the
   secret scope and on the Aurora role, run `create-connection.sh <env>`, then
   have the DB admin create the replication slot.
3. **One-line PR** here adding the env to `gp_api_mirror_connected_envs` in
   `variables.tf`, then **apply #2**: the connection grant, the gateway, the
   ingestion pipeline and the loop job. Do this soon after the slot exists;
   Aurora keeps every change for an unread slot.

The gateway starts when it is created, and the apply waits for it to reach
`RUNNING`. If it fails (no slot, bad password), Terraform deletes it and the
apply fails, so check the slot and connection before retrying.

The loop job is created unpaused. Its first runs may fail with "Timeout while
waiting for table token" while the gateway takes its first snapshot; they
catch up on their own. To pause or unpause it (for example around a manual
full refresh), find its ID and set `pause_status`. The next apply sets it back
to `UNPAUSED`.

```bash
databricks jobs list --name gp-api-mirror-dev-ingestion-loop
databricks jobs update --json '{"job_id": <id>, "new_settings": {"continuous": {"pause_status": "PAUSED"}}}'
```

### gp-api Postgres federation (Lakehouse Federation)

`gp_api_federation.tf` lets Databricks query gp-api's Aurora database (`gpdb`)
live, through a Unity Catalog connection and a foreign catalog. Nothing is
copied. The AWS and Postgres side (an internet-facing NLB in front of an RDS
Proxy, allowlisted to Databricks' outbound IPs, and the `databricks_federation`
role) and its runbook live in omni
(`packages/gp-api/deploy/databricks/federation/`). Serverless compute reaches
Aurora through that NLB, so nothing here configures the network.

| Env  | Foreign catalog | Connection    | Secret scope             | Readers group           |
| ---- | --------------- | ------------- | ------------------------ | ----------------------- |
| dev  | `gp_api_pg_dev` | `gp_api_dev`  | `gp-api-federation-dev`  | `gp_api_pg_dev_readers` |
| prod | `gp_api_pg`     | `gp_api_prod` | `gp-api-federation-prod` | `gp_api_pg_readers`     |

The catalogs expose users' personal data. The readers groups start empty and
are not nested into `data users`; add members in the console. The `gp_api`
and `dbt_cloud` service principals read both catalogs.

Terraform always manages the secret scopes and the readers groups. For each env
in `gp_api_federation_envs` (`dev` and `prod` by default) it also manages:

- the foreign catalog over database `gpdb`, using connection `gp_api_<env>`
- `USE_CATALOG`, `USE_SCHEMA` and `SELECT` on the catalog for the readers
  group, `gp_api` and `dbt_cloud`
- `USE_CONNECTION` and `CREATE_FOREIGN_CATALOG` on the connection for
  `github-action`, which creates the catalog. Readers need no connection grant
  to query on serverless or standard compute.

Stays outside Terraform, because each would put a credential in state or lives
in Postgres:

- the `databricks_federation` Postgres role's password (and `LOGIN`)
- the `postgres-password` value in each `gp-api-federation-<env>` scope, if
  the connection reads its password from there
- the Unity Catalog connections `gp_api_dev` and `gp_api_prod` (type
  `postgresql`, host = the NLB's DNS name from omni's stack output
  `databricksFederationHost`, port 5432, user `databricks_federation`,
  `sslmode` `verify-ca`, the Amazon root CAs), owned by `github-action`

Order. Steps 1 to 4 for both envs, then one Deploy:

1. **omni deploy** creates the env's NLB and RDS Proxy and the
   `databricks_federation` role (`NOLOGIN`). The NLB's DNS name is the stack
   output `databricksFederationHost`.
2. **Password**: a DB admin sets the role's password and `LOGIN`, and the
   same credentials go into omni's RDS Proxy secret (omni runbook).
3. **Secret** (optional): put that password in `gp-api-federation-<env>`, key
   `postgres-password`, only if the connection reads it from there.
4. **Connection**: a Databricks admin creates `gp_api_<env>` in Catalog
   Explorer with the settings above, skips the wizard's catalog step, and sets
   the owner to `github-action`.
5. **Merge** this change, once both connections exist. A Deploy before then
   fails at the catalog step.
6. **Deploy** (Actions → Deploy, uncheck "Dry run").
7. **Test** from a serverless SQL warehouse:
   `SELECT count(*) FROM gp_api_pg_dev.public.campaign`.

Removing an env from the list drops its catalog and grants. The connection,
scope and Postgres role stay.

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
| `DATABRICKS_CLIENT_ID` | Application ID of the `github-action` service principal |

There is no Databricks client secret. CI authenticates via GitHub OIDC using the
federation policies in `service_principals.tf` (`github_action_ci`). Each subject
is pinned to this repo: pull requests, `main`, and the `production` environment.

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
├── gp_api_mirror.tf           # gp-api Postgres mirror (Lakeflow Connect)
├── gp_api_federation.tf       # gp-api Postgres federation (foreign catalogs)
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
