# CLAUDE.md

Terraform for the GoodParty data platform: Databricks Unity Catalog (catalogs, schemas, grants, service principals, warehouses), Astronomer/Astro deployments, and the supporting AWS for the people-api loader (S3 bucket + IAM). Backend is S3 remote state; CI runs `terraform plan` on every PR, and apply is a gated post-merge `Deploy` workflow (Actions → Deploy, uncheck "Dry run").

## Conventions

- **Don't put ticket numbers in committed code.** No `DATA-1234`-style references in `.tf` files, resource names, tags, or comments. Describe *what* the resource is and *why* in the code; track the ticket in the PR title/description and commit message instead. (Pre-existing ticket references can be left until the surrounding code is next touched.)

## Grants

- `databricks_grants` (plural) is **authoritative** for a securable — it owns the complete grant set, so a singular `databricks_grant` on the same securable will fight it on the next apply. To add a principal to an already-authoritatively-managed schema/catalog, add a `grant` block to the existing `databricks_grants` resource rather than a separate `databricks_grant`.
