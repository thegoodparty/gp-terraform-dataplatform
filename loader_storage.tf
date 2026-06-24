# =============================================================================
# People-API loader storage — DATA-1905
#
# A dedicated S3 bucket the loader's `unload` step writes to (from Databricks, via
# the UC external location below) and the `copy` step reads from (from Aurora, via
# the rds-s3-import role). Governs Databricks access with a UC storage credential +
# external location and a dedicated loader service principal.
#
# IAM for the storage credential uses the Databricks-provided policy generators
# (databricks_aws_unity_catalog_policy / _assume_role_policy) rather than a
# hand-written cross-account trust — these emit the exact trust (Databricks UC
# master role + self-assumption) and S3 access policy UC requires.
# =============================================================================

data "aws_caller_identity" "current" {}

# --- S3 bucket -----------------------------------------------------------------

resource "aws_s3_bucket" "loader" {
  bucket = var.loader_s3_bucket

  # Project/ManagedBy come from the provider default_tags.
  tags = {
    Purpose = "people-api voter unload/load staging (DATA-1905)"
  }

  # The loader's data path — guard against an accidental destroy/recreate, matching the
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

# SSE-S3 (AES256). NOTE: SSE-KMS is deferred — it would require kms:Decrypt on both
# the UC storage-credential role and the rds-s3-import role; revisit if the data
# warrants a CMK.
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

  # Spark/Databricks writes the CSV parts via multipart upload; a failed unload can leave
  # incomplete uploads that the prefix-expiry rule never reaches. Reap them so they don't
  # accrue storage cost. Empty filter = whole bucket.
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
  role_name      = var.loader_uc_role_name
  external_id    = var.databricks_account_id
}

# S3 access policy scoped to the loader bucket.
data "databricks_aws_unity_catalog_policy" "loader" {
  aws_account_id = data.aws_caller_identity.current.account_id
  bucket_name    = var.loader_s3_bucket
  role_name      = var.loader_uc_role_name
}

resource "aws_iam_role" "loader_uc" {
  name               = var.loader_uc_role_name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.loader.json
  # Project/ManagedBy come from the provider default_tags.
}

# Inline policy: this UC access policy is 1:1 with the role and never shared, so an inline
# policy is simpler than a managed policy + attachment (and matches the rds-s3-import block below).
resource "aws_iam_role_policy" "loader_uc" {
  name   = "${var.loader_uc_role_name}-policy"
  role   = aws_iam_role.loader_uc.id
  policy = data.databricks_aws_unity_catalog_policy.loader.json
}

# --- UC storage credential + external location ---------------------------------

resource "databricks_storage_credential" "loader" {
  name    = var.loader_storage_credential_name
  comment = "People-API loader bucket access (DATA-1905)"
  aws_iam_role {
    role_arn = aws_iam_role.loader_uc.arn
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_external_location" "loader" {
  name = var.loader_external_location_name
  # Reference the bucket resource (not var.loader_s3_bucket) so the graph has a create-time edge
  # to the bucket — the value is identical, but it stops the create-time s3:ListBucket validation
  # from racing ahead of bucket creation (NoSuchBucket).
  url             = "s3://${aws_s3_bucket.loader.bucket}/"
  credential_name = databricks_storage_credential.loader.name
  comment         = "People-API loader exports (DATA-1905)"

  # The external location validates at create time with a real s3:ListBucket via the assumed
  # role. The inline S3 policy and the storage credential are sibling branches off the IAM role
  # with no edge between them, so without this Terraform could validate before the policy is
  # attached -> AccessDenied. (Orthogonal to IAM eventual-consistency, which may still need a re-apply.)
  depends_on = [aws_iam_role_policy.loader_uc]

  lifecycle {
    prevent_destroy = true
  }
}

# --- External location grant ---------------------------------------------------

# The dedicated loader service principal (databricks_service_principal.loader, defined in
# service_principals.tf with the other managed SPs) drives the unload warehouse and needs
# WRITE on the external location to INSERT OVERWRITE DIRECTORY into the bucket.
resource "databricks_grants" "loader_external_location" {
  external_location = databricks_external_location.loader.id

  grant {
    principal  = databricks_service_principal.loader.application_id
    privileges = ["READ_FILES", "WRITE_FILES"]
  }
}

# --- Aurora read (rds-s3-import role) ------------------------------------------

# The role Aurora assumes for aws_s3.table_import_from_s3 in the loader's `copy` step.
# Created here (rather than reusing the POC's dated rds-s3-import-<date> role) so the
# bucket and the role that reads it are managed together. Two out-of-band ties:
#   - the loader's LOADER_S3_IMPORT_ROLE_ARN must point at this role (rds_s3_import_role_arn output);
#   - the worker role's iam:PassRole grant (DATA-1856, scoped to rds-s3-import-*) must cover this
#     name so `provision`'s add-role-to-db-cluster can attach it.
resource "aws_iam_role" "rds_s3_import" {
  name = var.rds_s3_import_role_name

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
  # Project/ManagedBy come from the provider default_tags.
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
