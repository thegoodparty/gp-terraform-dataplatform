# Good Party Data Platform

Terraform configuration for managing the Good Party data infrastructure:
- **Databricks Unity Catalog** - Mart schemas and access control
- **Astronomer (Astro)** - Airflow deployments for orchestration

## Quick Start

### Prerequisites

- asdf (`brew install asdf`)
- Terraform ~> 1.14.4, managed by asdf via `.tool-versions`:
  ```bash
  asdf plugin add terraform
  asdf install
  ```
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

### Governed tags and the governance functions

Three governed tags are managed here. Each fixes the values it may hold, so an
ABAC policy can match on it without trusting every writer to spell the value.

| Tag key | Allowed values | Goes on | Propagation |
| ------- | -------------- | ------- | ----------- |
| `sensitive` | `identifier`, `confidential` | columns | on, default `confidential` |
| `classified` | `true` | tables | on, default `true` |
| `open` | `true` | columns | off |

**Propagation is a console step.** Neither Terraform nor the tags API can set it:
the tag policy object carries only the key, description and allowed values. A
workspace admin who can see the tag still needs MANAGE to change this, which
account admins hold. Once, after the apply, for each tag in the table:

1. Catalog > **Govern** > **Governed Tags** > the tag > **Configure**.
2. Turn **Tag propagation** on.
3. For `sensitive` set the **Default propagation value** to `confidential`; for
   `classified`, `true`. `open` stays off with no default: propagating it would
   let a column built from an open and a sensitive input come through in the
   clear.
4. **Save**.

Until this is done the tags are governed but inert: a tag set directly still
enforces, and nothing flows downstream.

**Who may write a governed tag.** Every write needs ASSIGN, including re-setting
a value that is already there, and dbt re-sets its tags on every build. So
`dbt_cloud` holds `roles/tagPolicy.assigner` on all three tags, granted in
`governed_tags.tf` through each tag's rule set. That rule set is authoritative:
the creator's `roles/tagPolicy.manager` entry is declared there too, because
leaving it out would drop it on the next apply. Adding another principal means
another `grant_rules` block in that file, not a grant in the console.

A new grant takes one to two minutes to take effect, so a build that re-sets a
tag in the couple of minutes after an apply can fail with `PERMISSION_DENIED`
and succeed on retry.

Known limit: only account admins and `dbt_cloud` hold ASSIGN. A developer who is
not an account admin cannot rebuild a tagged model in a personal schema. That is
deliberate, because ASSIGN on `open` becomes a way around a mask once the mask
policies exist.

**The functions** live in `governance`, created and owned by `dbt_cloud` from
`gp-data-platform` (`models/governance/`), not here: the provider has no Unity
Catalog function resource. Terraform creates the schema and grants `dbt_cloud`
the `CREATE_FUNCTION` its catalog grant lacks, because a build that cannot
create the function fails on the first run. Analyst holds `USE_SCHEMA` and
`EXECUTE` on the schema, which is what lets a person or agent working as analyst
call `governance.pseudonym(...)` to look a row up.

**The salt** is a table in the same schema: `pseudonym_salt`, one row per
rotation, `version` and `salt`. Terraform creates it empty and owns it, so no dbt
build can recreate it. A dbt-built salt table would be dropped by any
`dbt build --full-refresh` that selected it, and every masked identifier would
come back null with no error anywhere.

Seed it once, after Deploy, from the SQL editor or a Databricks shell. The value
is generated by the warehouse, so it is never typed, pasted or printed.

The seed is three statements, in this order. `data-engineers` holds `MANAGE` on
the catalog but not `MODIFY` on the table, and `MANAGE` covers granting and
dropping, not writes: `MANAGE` does not imply any data privilege. So grant
yourself `MODIFY`, insert, then revoke, which leaves the standing grant set as
Terraform declares it.

```sql
-- 1. The data privilege the insert needs.
grant modify on table goodparty_data_catalog.governance.pseudonym_salt
to `sanjay@goodparty.org`;

-- 2. Seed version 1, exactly once.
insert into goodparty_data_catalog.governance.pseudonym_salt
select 1, sha2(concat(uuid(), uuid()), 256)
where not exists (select 1 from goodparty_data_catalog.governance.pseudonym_salt where version = 1);

-- 3. Put the grants back.
revoke modify on table goodparty_data_catalog.governance.pseudonym_salt
from `sanjay@goodparty.org`;
```

Check it read counts and lengths only (`select count(*), count_if(salt is not
null), count(distinct version)` gives `1, 1, 1`), never the value, and never
the `salt` column itself. Version 1 was seeded this way on 2026-11-17 and the
temporary `MODIFY` grant was revoked afterwards, so the table now carries no
grants of its own.

Two rules about that table:

- **Never select the `salt` column.** Not from a check, not from an agent, not
  to debug. Agents here run on a person's login, which can read it, and the
  models behind them are third-party. Every verification reads a count or a
  length instead.
- **Its `classified` tag is the open question below, not a settled rule.** An
  earlier version of this section said "never tag it `classified`" on the grounds
  that it "must stay closed to every masked principal". That reason is already
  untrue: analyst holds catalog-wide `SELECT` and `USE_SCHEMA`, so analyst can
  read this table directly today whatever its tags say. Treat the tag as a
  decision waiting on the masking verification, described next.

**The salt table versus the unclassified row filter. Read this before trusting a
masked read.**

`pseudonym` reads `governance.pseudonym_salt` in a subquery. Unity Catalog checks
access to a table read inside a function against the function's owner, but
evaluates policies against the **querying user**. `closed_until_classified`
applies to every table in the catalog that does not carry `classified = true`,
and the salt table carries no tags. So for an `analyst` session the subquery is
filtered to no rows and `pseudonym` returns null for every input, silently: no
error, and every join on a hashed email stops matching.

Note which way the filter runs. The row filter is
`not has_tag_value('classified', 'true')`, so `classified = true` is what
**exempts** a table. Leaving the salt untagged is what breaks the mask; tagging
it is what fixes it. That is the opposite of what intuition suggests, and it is
the reason the old "never tag it" rule was worth re-reading rather than copying.

Two ways out, and the choice is deliberate:

1. **Tag `pseudonym_salt` `classified = true`.** One tag assignment on one
   Terraform-owned table. The subquery then reads, and the identifier mask works.
   The cost is nil beyond what already exists: the policies apply only to
   `analyst`, and `analyst` already reaches this table through catalog `SELECT`.
2. **Exempt it by a dedicated tag rather than by `classified`,** for example a
   table-level `open = true` with the row filter widened to
   `not has_tag_value('classified', 'true') and not has_tag_value('open', 'true')`.
   More moving parts, and `open` does not propagate, so the exemption stays local
   to the object it is set on.

Neither is applied here. This PR adds the policies and leaves the salt untagged,
because the tag is a classification decision rather than a consequence of the
policy shape, and because nobody is in `analyst` to be affected. The masking
verification measures `length(governance.pseudonym(...))` first, before any other
check, and it is what forces this decision.

To rotate, change the `1` to the next version in both the `select` and the
`not exists` test, run it, then point `pseudonym` at the new version: insert the
row first, then rebuild the function, never the other way round. Rotation
invalidates every previous hash at once, which is the point, and also breaks any
saved lookup or stored join key built on one.

### The analyst masking policies

Three ABAC policies sit on `goodparty_data_catalog` and apply to the `analyst`
role group only. Two are column masks: `mask_identifier` sends every column
tagged `sensitive = identifier` through `governance.pseudonym`, and
`mask_confidential` sends every column tagged `sensitive = confidential` through
`governance.redact`. Both skip a column that carries the `open` tag. The third,
`closed_until_classified`, is a row filter: a table that does not carry
`classified = true` returns no rows.

Each names `analyst` in `TO` and `pii_viewer` in `EXCEPT`. The four higher roles
are nested inside `analyst`, so its reach is all five; `EXCEPT pii_viewer` takes
`pii_viewer` and the `transformer` nested inside it back out. `pii_services` and
`ingestor` are deliberately not exempt here: `pii_services` does not exist yet,
and an `ingestor` exemption on this catalog would cover the marts as well as
raw. Both arrive in the catalog split.

**Applying these changes nothing for anyone yet.** The policies act only on
principals in `TO`, and every role group is empty. Do not read a successful
apply as "the roll-out is done": the day the first person joins `analyst`, a
table nobody has classified returns no rows, and that is most of the catalog
today.

**The order matters, and it is a hard order.** The functions must exist before
the policies are created, because a policy names one and a missing function
fails the create. The salt must have its row before anything is masked, because
an empty salt table makes `pseudonym` return null for every input with no error
anywhere. So: merge and build the functions, seed the salt, then Deploy this
stack. As of 2026-11-17 the functions exist and version 1 is seeded.

**Who may do what.** Creating a policy needs `MANAGE` on the catalog and
`EXECUTE` on the function; that is why `github-action` holds both, and why `admin`
role membership is not required. The catalog's owner is a person, so CI changes
grants today through admin rights rather than ownership, and the explicit
`MANAGE` means policy creation rests on a declared grant instead. Calling a
function is narrower: `analyst` and its nested roles, `dbt_cloud`, and
`github-action`. `data-engineers` cannot call `pseudonym` to look a row up, and
neither can a developer's own identity. Lookups go through the roles by design:
a person runs as `analyst` and calls `governance.pseudonym('someone@example.org')`
from there.

**One hazard to know before trusting a masked read.** See "The salt table versus
the unclassified row filter" above: the salt table is unfiltered today, which is
exactly what would make `pseudonym` return null inside an analyst session. The
masking verification measures a masked identifier's length before it trusts
anything else.

**dbt replaces the functions on every prod build.** `models/governance/` builds
with `create or replace function`, and a policy that names a function being
replaced is the case the docs warn about. If a build ever makes the policies
stop applying, every query in scope fails rather than returning clear data, and
the fix belongs in the build order, not in a manual re-create.

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
├── governance.tf              # governance schema, its grants, the pseudonym salt
├── governed_tags.tf           # governed tags and their ASSIGN rule sets
├── groups.tf                  # Databricks groups
├── locals.tf                  # Local values + Astro environment configs
├── gp_api_mirror.tf           # gp-api Postgres mirror (Lakeflow Connect)
├── gp_api_federation.tf       # gp-api Postgres federation (foreign catalogs)
├── outputs.tf                 # Terraform outputs
├── permissions.tf             # Databricks grants
├── policies.tf                # the analyst masking and row-filter policies
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
