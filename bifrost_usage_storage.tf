# =============================================================================
# Bifrost usage export: read access from Unity Catalog
# =============================================================================
# The Bifrost gateway keeps one row per model request in its own Postgres, inside
# the workbench AWS account. A scheduled job there writes one Parquet object per
# run to a bucket that account owns, and the Airflow loader reads those objects
# with COPY INTO. This file is the Databricks side of that read: an IAM role, a
# storage credential that wraps it, an external location scoped to the export
# prefix, and the grant that lets the loader's service principals use it.
#
# Nothing here writes. The credential is read_only, and the role's S3 permissions
# are Get and List only, so two independent things would have to be wrong at once
# for a Databricks job to modify the export.
#
# ## The trust is generated, and the order is a chain
#
# The credential takes the role ARN as a constructed string, so it does not depend
# on the role resource. The assume-role-policy data source reads the credential's
# computed external_id, so it depends on the credential having been created. The
# role reads that data source. Terraform therefore creates the credential first,
# then the role with its finished trust, in one apply.
#
# skip_validation on the credential is required rather than cosmetic: its create
# call validates by default, and at that instant the role it names does not exist
# yet. The proof is not deferred to the loader, though — creating the external
# location below validates by default too, which assumes the role through the
# credential's external ID and lists the prefix. So an apply that succeeds has
# proven the read path end to end; the loader's first COPY INTO is a second
# check, not the only one. If a plan ever reports a cycle, the fallback is two
# applies and the PR says so.
#
# ## IAM propagation
#
# The role policy and the external location are created seconds apart in one
# apply, and a brand-new IAM policy is eventually consistent: a call that
# exercises the role immediately after the write can see AccessDenied. The short
# sleep between them absorbs that, so the apply either succeeds fully or fails
# loudly instead of failing intermittently on a first run.
#
# ## The bucket lives in the other account
#
# The bucket, its policy and its prefix are created by thegoodparty/ops in the
# workbench account. This file names them and never manages them. The bucket
# policy there admits this role by an aws:PrincipalArn condition, which is why the
# role's account matters: it is the account this configuration deploys into, and
# `data.aws_caller_identity.current` is what proves which that is.

locals {
  # The prefix the export writes to. Thegoodparty/ops owns the bucket and both
  # halves of this name; they must match its module's constants and the loader's
  # bifrost_export_bucket / bifrost_export_prefix Airflow Variables. Two different
  # failures follow a drift: if the Airflow Variables disagree, COPY INTO reads an
  # empty location and succeeds with zero rows; if the bucket or prefix here
  # disagrees with the ops bucket, the external location's own validation fails at
  # apply, which is the louder and better one.
  bifrost_usage_bucket = "goodparty-workbench-bifrost-usage"
  bifrost_usage_prefix = "bifrost/logs"

  # The role's account is this configuration's own account, resolved rather than
  # written down: the bucket policy in the workbench account pins this ARN, so a
  # wrong account here is a read that fails with a permission error on an object
  # that is plainly there.
  bifrost_usage_role_name = "bifrost-usage-export-reader"
  bifrost_usage_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.bifrost_usage_role_name}"

  bifrost_usage_tags = { Project = "bifrost-usage-export" }
}

# The credential first: it takes a constructed ARN, so it depends on nothing.
resource "databricks_storage_credential" "bifrost_usage" {
  name      = local.bifrost_usage_role_name
  read_only = true
  comment   = "Reads the Bifrost usage export prefix in the workbench account, for the finance mart's request log."

  aws_iam_role {
    role_arn = local.bifrost_usage_role_arn
  }

  # Required, not cosmetic. Creating a credential validates the role it names, and
  # at this point the role resource below has not been created. Validation comes
  # back on at the external location, which is what proves the trust.
  skip_validation = true
}

# The trust, generated from the credential's external ID. This is the edge that
# makes the order a chain: credential -> this -> role.
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

# Two statements, and the second is the one that is easy to omit.
#
# The first is the read itself: objects under the prefix, and ListBucket scoped by
# s3:prefix so the credential cannot enumerate the bucket.
#
# The second is sts:AssumeRole on the role's own ARN. The generated trust's second
# statement makes the role self-assuming with the account root as the principal,
# and a trust naming the account root delegates the decision to the account's
# identity policies. Without this statement the self-assume is denied even though
# the trust permits it, which fails at the first COPY INTO rather than at apply.
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
        # Bucket-level, and nothing else is. Databricks' own S3 policy for a Unity
        # Catalog external location grants it, and its validation path uses it to
        # resolve the bucket's region; without it the apply-time validation can
        # fail on a bucket that is otherwise readable.
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
  # Restated on the location as well as the credential: the API models both, and a
  # location defaults to read-write. The credential's flag is what Databricks
  # documents as the one that matters, and this makes the intent legible from
  # either object rather than requiring a reader to look through to the other.
  read_only = true
  # Holds no data of its own: removing this pointer deletes nothing in S3.
  force_destroy = true

  depends_on = [time_sleep.bifrost_usage_iam_propagation]
}

# READ FILES is what COPY INTO needs, and it runs as the airflow service
# principals: this is the half that keeps Astro out of the workbench bucket
# entirely, because the listing and the reading both happen inside Databricks.
# Deliberately not granted to data users or data engineers: the mart is what they
# read, not the raw landing.
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
