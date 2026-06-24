# =============================================================================
# People-API loader storage — DATA-1905
#
# A dedicated S3 bucket the loader's `unload` step writes to (from Databricks, via
# the UC external location below) and the `copy` step reads from (from Aurora, via
# the rds-s3-import role), governed by a UC storage credential + external location.
#
# IAM for the storage credential uses the Databricks-provided policy generators,
# which emit the exact cross-account trust and S3 policy UC requires.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  # Single-environment resource names. loader_s3_bucket MUST match the loader's
  # LOADER_S3_BUCKET env var; the bucket is region-suffixed for global uniqueness.
  loader_s3_bucket               = "gp-people-loader-us-west-2"
  loader_uc_role_name            = "gp-people-loader-uc-access"
  loader_storage_credential_name = "people-loader-s3"
  loader_external_location_name  = "people-loader"
  # rds-s3-import-* prefix is load-bearing: the worker role's iam:PassRole grant
  # (DATA-1856) is scoped to that prefix.
  rds_s3_import_role_name = "rds-s3-import-people-loader"

  loader_tags = { Project = "gp-people-loader" }
}

# --- S3 bucket -----------------------------------------------------------------

resource "aws_s3_bucket" "loader" {
  bucket = local.loader_s3_bucket
  tags   = merge(local.loader_tags, { Purpose = "people-api voter unload/load staging (DATA-1905)" })

  # The loader's data path — guard against accidental destroy/recreate, matching the
  # repo's convention on persistent stores (catalogs/schemas/volumes).
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "loader" {
  bucket                  = aws_s3_bucket.loader.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (AES256). SSE-KMS is deferred (would add kms:Decrypt to the UC and
# rds-s3-import roles); revisit if the data warrants a CMK.
resource "aws_s3_bucket_server_side_encryption_configuration" "loader" {
  bucket = aws_s3_bucket.loader.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Per-run exports (voter_export_<date>/) are disposable once cutover completes.
resource "aws_s3_bucket_lifecycle_configuration" "loader" {
  bucket = aws_s3_bucket.loader.id

  rule {
    id     = "expire-voter-exports"
    status = "Enabled"
    filter {
      prefix = "voter_export_"
    }
    expiration {
      days = var.loader_export_lifecycle_days
    }
  }

  # Reap failed-unload multipart uploads the prefix-expiry rule never reaches.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# --- IAM role Databricks Unity Catalog assumes ---------------------------------

# Trust policy (Databricks UC master role + the role's self-assumption). external_id
# is the Databricks account id for an account-level storage credential.
data "databricks_aws_unity_catalog_assume_role_policy" "loader" {
  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = local.loader_uc_role_name
  external_id    = var.databricks_account_id
}

# S3 access policy scoped to the loader bucket.
data "databricks_aws_unity_catalog_policy" "loader" {
  aws_account_id = data.aws_caller_identity.current.account_id
  bucket_name    = local.loader_s3_bucket
  role_name      = local.loader_uc_role_name
}

resource "aws_iam_role" "loader_uc" {
  name               = local.loader_uc_role_name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.loader.json
  tags               = local.loader_tags
}

# Inline policy: 1:1 with the role and never shared, so simpler than a managed
# policy + attachment (matches the rds-s3-import block below).
resource "aws_iam_role_policy" "loader_uc" {
  name   = "${local.loader_uc_role_name}-policy"
  role   = aws_iam_role.loader_uc.id
  policy = data.databricks_aws_unity_catalog_policy.loader.json
}

# --- UC storage credential + external location ---------------------------------

resource "databricks_storage_credential" "loader" {
  name    = local.loader_storage_credential_name
  comment = "People-API loader bucket access (DATA-1905)"
  aws_iam_role {
    role_arn = aws_iam_role.loader_uc.arn
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_external_location" "loader" {
  name = local.loader_external_location_name
  # Reference the bucket resource (not the literal) so the graph has a create-time edge
  # to the bucket, stopping the create-time s3:ListBucket validation from racing ahead of
  # bucket creation (NoSuchBucket).
  url             = "s3://${aws_s3_bucket.loader.bucket}/"
  credential_name = databricks_storage_credential.loader.name
  comment         = "People-API loader exports (DATA-1905)"

  # The external location validates at create time with a real s3:ListBucket via the assumed
  # role. The inline policy and the storage credential are sibling branches off the IAM role
  # with no edge between them, so without this Terraform could validate before the policy is
  # attached -> AccessDenied. (Orthogonal to IAM eventual-consistency, which may still need a re-apply.)
  depends_on = [aws_iam_role_policy.loader_uc]

  lifecycle {
    prevent_destroy = true
  }
}

# Grants on this external location live in permissions.tf with the repo's other grants.

# --- Aurora read (rds-s3-import role) ------------------------------------------

# The role Aurora assumes for aws_s3.table_import_from_s3 in the loader's `copy` step.
# Created here (rather than reusing the POC's dated rds-s3-import-<date> role) so the
# bucket and the role that reads it are managed together. Two out-of-band ties:
#   - the loader's LOADER_S3_IMPORT_ROLE_ARN must point at this role (rds_s3_import_role_arn output);
#   - the worker role's iam:PassRole grant (DATA-1856, scoped to rds-s3-import-*) must cover this
#     name so `provision`'s add-role-to-db-cluster can attach it.
resource "aws_iam_role" "rds_s3_import" {
  name = local.rds_s3_import_role_name
  tags = local.loader_tags

  # Trust RDS to assume the role, guarding against the confused-deputy problem:
  #   - SourceAccount pins the calling account;
  #   - SourceArn (ArnLike) pins the source to the loader's own clusters. The loader names
  #     every provisioned cluster gp-people-db-<run_date> (config.py new_cluster_id), so the
  #     prefix wildcard covers each run and the gp-people-db-prod serving cluster without
  #     blocking the per-run train-deployment replacements.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "rds.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:${var.loader_db_cluster_prefix}-*"
          }
        }
      },
    ]
  })
}

# Read on the loader bucket so table_import_from_s3 can pull the CSV parts.
resource "aws_iam_role_policy" "rds_s3_import" {
  name = "s3-import"
  role = aws_iam_role.rds_s3_import.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.loader.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.loader.arn}/*"
      },
    ]
  })
}
