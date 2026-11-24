# Read-only access to the usage export bucket, which lives in the workbench
# account and is owned by thegoodparty/ops. That repo's bucket policy admits this
# role by aws:PrincipalArn, so the role's account is the one this deploys into.
#
# One role and one storage credential read two prefixes for two exporters, the
# Bifrost gateway's and the delegate swarm's, so each gets its own external
# location.
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

  # Must match the parent of thegoodparty/ops' SWARM_EXPORT_PREFIXES, which are
  # delegate-swarm/session-cost and delegate-swarm/task-edge. A sibling of
  # bifrost/logs rather than a child of it: Unity Catalog refuses an external
  # location nested inside another, which is why this is a second location and
  # not a subpath of the first.
  delegate_swarm_prefix = "delegate-swarm"

  # What the role reads, and the whole of it. Wider than the bucket policy, which
  # admits only the swarm's two table prefixes under delegate-swarm/.
  usage_read_prefixes = [local.bifrost_usage_prefix, local.delegate_swarm_prefix]

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
  comment   = "Reads the usage export prefixes in the workbench account: the Bifrost gateway's and the delegate swarm's."

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
  description = "Assumed by Databricks (Unity Catalog) to read the usage export prefixes."
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
          for prefix in local.usage_read_prefixes :
          "arn:aws:s3:::${local.bifrost_usage_bucket}/${prefix}/*"
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
            # Both the location root and its contents: Databricks lists each
            # location's prefix when it validates one.
            "s3:prefix" = flatten([
              for prefix in local.usage_read_prefixes : [prefix, "${prefix}/*"]
            ])
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
  read_only       = true
  # Holds no data of its own: removing this pointer deletes nothing in S3.
  force_destroy = true

  depends_on = [time_sleep.bifrost_usage_iam_propagation]
}

# The swarm's two table prefixes sit under one location, because a location may be
# read at a subpath: each loader's COPY INTO names delegate-swarm/session-cost/ or
# delegate-swarm/task-edge/ below this root.
resource "databricks_external_location" "delegate_swarm_usage" {
  name            = "delegate_swarm_usage_export"
  url             = "s3://${local.bifrost_usage_bucket}/${local.delegate_swarm_prefix}"
  credential_name = databricks_storage_credential.bifrost_usage.name
  comment         = "Delegate swarm usage export, read-only. Written by the swarm host's own scheduled job."
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

# The same principals and the same privilege, on the other location. Grant sets are
# per securable, so this has to be its own resource; a grant on the Bifrost location
# reaches nothing under delegate-swarm/.
resource "databricks_grants" "delegate_swarm_usage_external_location" {
  external_location = databricks_external_location.delegate_swarm_usage.id

  dynamic "grant" {
    for_each = databricks_service_principal.airflow
    content {
      principal  = grant.value.application_id
      privileges = ["READ_FILES"]
    }
  }
}
