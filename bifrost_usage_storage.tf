# Read-only access to the Bifrost usage export bucket, which lives in the workbench
# account and is owned by thegoodparty/ops. That repo's bucket policy admits this
# role by aws:PrincipalArn, so the role's account is the one this deploys into.
#
# Apply order is credential -> assume-role-policy data source -> role, because the
# trust needs the credential's computed external_id. skip_validation on the
# credential is therefore required: its create validates a role that does not exist
# yet. The external location keeps validation on, so a successful apply proves the
# read path.

locals {
  # Must match thegoodparty/ops' module constants and the loader's
  # bifrost_export_bucket / bifrost_export_prefix Variables. A drift with the
  # Variables reads zero rows and succeeds; a drift here fails validation at apply.
  bifrost_usage_bucket = "goodparty-workbench-bifrost-usage"
  bifrost_usage_prefix = "bifrost/logs"

  # Resolved, not written down: the workbench bucket policy pins this ARN, and a
  # wrong account denies every read.
  bifrost_usage_role_name = "bifrost-usage-export-reader"
  bifrost_usage_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.bifrost_usage_role_name}"

  bifrost_usage_tags = { Project = "bifrost-usage-export" }
}

# First: takes a constructed ARN, so it depends on nothing.
resource "databricks_storage_credential" "bifrost_usage" {
  name      = local.bifrost_usage_role_name
  read_only = true
  comment   = "Reads the Bifrost usage export prefix in the workbench account, for the finance mart's request log."

  aws_iam_role {
    role_arn = local.bifrost_usage_role_arn
  }

  # Required: create validates the named role, which does not exist yet. The
  # external location validates the trust instead.
  skip_validation = true
}

# The edge that makes the order a chain: credential -> this -> role.
data "databricks_aws_unity_catalog_assume_role_policy" "bifrost_usage" {
  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = local.bifrost_usage_role_name
  external_id    = databricks_storage_credential.bifrost_usage.aws_iam_role[0].external_id
}

resource "aws_iam_role" "bifrost_usage" {
  name        = local.bifrost_usage_role_name
  description = "Assumed by Databricks (Unity Catalog) to read the Bifrost usage export prefix."
  tags        = local.bifrost_usage_tags

  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.bifrost_usage.json
}

# The sts:AssumeRole statement is easy to omit and required: the generated trust's
# self-assume names the account root, which delegates the decision to the account's
# identity policies, so without it the self-assume is denied despite the trust.
resource "aws_iam_role_policy" "bifrost_usage" {
  name = "bifrost-usage-export-read"
  role = aws_iam_role.bifrost_usage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadExportObjects"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = [
          "arn:aws:s3:::${local.bifrost_usage_bucket}/${local.bifrost_usage_prefix}/*",
        ]
      },
      {
        # Databricks' validation resolves the bucket's region with this; without it
        # the apply-time check can fail on a bucket that is otherwise readable.
        Sid      = "ReadBucketLocation"
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = "arn:aws:s3:::${local.bifrost_usage_bucket}"
      },
      {
        Sid      = "ListExportPrefix"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${local.bifrost_usage_bucket}"
        Condition = {
          StringLike = {
            "s3:prefix" = ["${local.bifrost_usage_prefix}/*", local.bifrost_usage_prefix]
          }
        }
      },
      {
        Sid      = "SelfAssumeForUnityCatalog"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.bifrost_usage_role_arn
      },
    ]
  })
}

# IAM propagation, before anything exercises the role. A policy written in this
# same apply is not always enforceable on the next call.
resource "time_sleep" "bifrost_usage_iam_propagation" {
  depends_on      = [aws_iam_role_policy.bifrost_usage]
  create_duration = "15s"
}

resource "databricks_external_location" "bifrost_usage" {
  name            = "bifrost_usage_export"
  url             = "s3://${local.bifrost_usage_bucket}/${local.bifrost_usage_prefix}"
  credential_name = databricks_storage_credential.bifrost_usage.name
  comment         = "Bifrost gateway usage export, read-only. Written by a scheduled job in the workbench account."
  # Set on both credential and location because a location defaults to read-write.
  read_only = true
  # Holds no data of its own: removing this pointer deletes nothing in S3.
  force_destroy = true

  depends_on = [time_sleep.bifrost_usage_iam_propagation]
}

# READ FILES is what COPY INTO needs, and it runs as the airflow service principals,
# so Astro never touches the workbench bucket. Not granted to data users or data
# engineers: they read the mart, not the raw landing.
resource "databricks_grants" "bifrost_usage_external_location" {
  external_location = databricks_external_location.bifrost_usage.id

  dynamic "grant" {
    for_each = databricks_service_principal.airflow
    content {
      principal  = grant.value.application_id
      privileges = ["READ_FILES"]
    }
  }
}
