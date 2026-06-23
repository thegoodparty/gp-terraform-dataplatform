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
    Purpose = "people-api voter unload/load staging (DATA-1640)"
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
  name            = var.loader_external_location_name
  url             = "s3://${var.loader_s3_bucket}/"
  credential_name = databricks_storage_credential.loader.name
  comment         = "People-API loader exports (DATA-1905)"

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

# --- Aurora read (optional until the rds-s3-import role name is confirmed) ------

# Extends the existing rds-s3-import role (DATA-1856, created AWS-side) with read on
# the loader bucket so `copy`'s aws_s3.table_import_from_s3 can import. The role
# itself is not managed here — only this inline policy. Skipped while the var is "".
resource "aws_iam_role_policy" "rds_s3_import_loader_read" {
  count = var.rds_s3_import_role_name != "" ? 1 : 0
  name  = "people-loader-bucket-read"
  role  = var.rds_s3_import_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.loader.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.loader.arn
      },
    ]
  })
}
