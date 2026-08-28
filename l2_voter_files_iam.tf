# =============================================================================
# L2 voter-file staging role
#
# The role the load_l2_voter_files DAG assumes (via Astro workload identity) to
# stage L2's SFTP archives in S3. Databricks then reads them back through the
# Unity Catalog external location, not through this role, so it needs no read
# path of its own beyond verifying its own writes.
#
# Replaces an IAM user with a static access key that was created by hand to get
# the first end-to-end test moving. One role per Airflow environment, matching
# gp-people-rds-admin-<env> in loader_iam.tf.
# =============================================================================

locals {
  l2_voter_files_bucket = "goodparty-warehouse-databricks"
  l2_voter_files_prefix = "l2_data"
  l2_voter_files_tags   = { Project = "gp-l2-voter-files" }
}

resource "aws_iam_role" "l2_voter_files" {
  for_each = local.astro_workload_identities

  name        = "gp-l2-voter-files-${each.key}"
  description = "Assumed by the L2 voter-file DAG to stage SFTP archives in S3 (${each.key})."
  tags        = local.l2_voter_files_tags

  assume_role_policy = local.astro_assume_role_policy[each.key]
}

resource "aws_iam_role_policy" "l2_voter_files" {
  for_each = local.astro_workload_identities

  name = "l2-staging-rw"
  role = aws_iam_role.l2_voter_files[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "L2StagingList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${local.l2_voter_files_bucket}"
        Condition = {
          StringLike = {
            "s3:prefix" = ["${local.l2_voter_files_prefix}/*"]
          }
        }
      },
      {
        # No DeleteObject: the DAG only ever adds staged snapshots, and pruning old
        # ones is not something it does today.
        Sid    = "L2StagingObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          # A failed multipart upload of a multi-GB archive member cleans itself up.
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource = "arn:aws:s3:::${local.l2_voter_files_bucket}/${local.l2_voter_files_prefix}/*"
      },
    ]
  })
}
