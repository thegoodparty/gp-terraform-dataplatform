# =============================================================================
# People-API loader admin role
#
# The role Airflow assumes (via Astro workload identity) to provision and manage
# the loader's RDS clusters and to read/write its S3 exports + SSM connection
# strings. One role per Airflow environment; both live in this single AWS account
# and are told apart by the Environment tag/condition.
#
# Previously split across tools: the role + `rds-admin` policy were defined in the
# omni Pulumi people-api stack, while `loader-s3-ssm` and `loader-provision` were
# hand-added to the dev role only (prod had neither, so the prod DAG failed at the
# first S3 read). This consolidates all loader IAM here, alongside the loader
# bucket and rds-s3-import role in loader_storage.tf.
# =============================================================================

locals {
  loader_cluster_prefix = "gp-people-db-20"

  # Cluster resource ARNs the loader creates/manages (config.py new_cluster_id is
  # gp-people-db-<run_date>). Shared by the rds-admin and loader-provision policies.
  loader_rds_cluster_arns = [
    "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:${local.loader_cluster_prefix}*",
    "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:db:${local.loader_cluster_prefix}*",
    "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster-pg:${local.loader_cluster_prefix}*",
  ]

  # The single CMK the people-db clusters are encrypted with (shared dev+prod).
  loader_cluster_kms_key_arn = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/a728ea20-f375-4039-b7c1-ef9ff192abcc"

  # The subnet group the loader provisions clusters into. LOADER_DB_SUBNET_GROUP is
  # a workspace-scoped Astro env var shared by both deployments (no per-env override),
  # so a single value covers dev and prod.
  loader_db_subnet_group = "api-master-rds-subnet-group"
}

resource "aws_iam_role" "rds_admin" {
  for_each = local.astro_workload_identities

  name        = "gp-people-rds-admin-${each.key}"
  description = "Assumed by Airflow DAGs to provision and manage people-api RDS resources (${each.key})."
  tags        = local.loader_tags

  assume_role_policy = local.astro_assume_role_policy[each.key]
}

# RDS create/modify + PassRole for the rds-s3-import role. Scoped to the loader's
# own clusters and tagged for this environment.
resource "aws_iam_role_policy" "rds_admin" {
  for_each = local.astro_workload_identities

  name = "rds-admin"
  role = aws_iam_role.rds_admin[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RdsCreate"
        Effect   = "Allow"
        Action   = ["rds:CreateDBCluster", "rds:CreateDBInstance"]
        Resource = local.loader_rds_cluster_arns
        Condition = {
          StringEquals = {
            "aws:RequestTag/managedBy"   = "dataplatform"
            "aws:RequestTag/Environment" = each.key
          }
        }
      },
      {
        Sid    = "RdsModifyAndSuspend"
        Effect = "Allow"
        Action = [
          "rds:AddRoleToDBCluster",
          "rds:RemoveRoleFromDBCluster",
          "rds:ModifyDBCluster",
          "rds:ModifyDBInstance",
          "rds:RebootDBCluster",
          "rds:RebootDBInstance",
          "rds:StopDBCluster",
          "rds:StopDBInstance",
          "rds:StartDBCluster",
          "rds:StartDBInstance",
        ]
        Resource = local.loader_rds_cluster_arns
        Condition = {
          StringEquals = {
            "aws:ResourceTag/managedBy"   = "dataplatform"
            "aws:ResourceTag/Environment" = each.key
          }
        }
      },
      {
        Sid      = "LoaderPassRoleForRDS"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/rds-s3-import-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "rds.amazonaws.com"
          }
        }
      },
    ]
  })
}

# S3 access to the loader bucket, SSM read/write on this env's connection-string
# parameters, and KMS decrypt of those SecureStrings via SSM.
resource "aws_iam_role_policy" "loader_s3_ssm" {
  for_each = local.astro_workload_identities

  name = "loader-s3-ssm"
  role = aws_iam_role.rds_admin[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LoaderS3List"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.loader.arn
      },
      {
        Sid      = "LoaderS3Objects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.loader.arn}/*"
      },
      {
        Sid    = "LoaderSsmConnStrings${title(each.key)}"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          # promote labels the new serving-parameter version `build-<date>` and moves the `live`
          # pointer people-api reads onto it at cutover.
          "ssm:LabelParameterVersion",
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/people-db-connection-string-${each.key}",
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/people-db-connection-string-${each.key}-20*",
        ]
      },
      {
        Sid    = "LoaderKmsForSsmSecureStrings"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        # KMS via SSM only; scoped by the ViaService condition rather than key ARN
        # because SSM chooses the account default key for these SecureStrings.
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

# RDS describe/create/delete for the provision + resize + teardown steps, PassRole
# for the rds-s3-import role Aurora COPY assumes, and use of the cluster CMK.
resource "aws_iam_role_policy" "loader_provision" {
  for_each = local.astro_workload_identities

  name = "loader-provision"
  role = aws_iam_role.rds_admin[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RdsProvisionRead"
        Effect   = "Allow"
        Action   = ["rds:DescribeDBClusters", "rds:DescribeDBInstances", "ec2:DescribeVpcEndpoints"]
        Resource = "*"
      },
      {
        Sid    = "RdsProvisionCreateTagged"
        Effect = "Allow"
        Action = [
          "rds:CreateDBClusterParameterGroup",
          "rds:CreateDBCluster",
          "rds:CreateDBInstance",
          "rds:AddTagsToResource",
        ]
        Resource = concat(local.loader_rds_cluster_arns, [
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subgrp:${local.loader_db_subnet_group}",
        ])
        Condition = {
          StringEquals = {
            "aws:RequestTag/Environment" = each.key
            "aws:RequestTag/managedBy"   = "dataplatform"
          }
        }
      },
      {
        Sid    = "RdsProvisionManage"
        Effect = "Allow"
        Action = [
          "rds:DeleteDBCluster",
          "rds:AddRoleToDBCluster",
          # teardown: delete the writer instance, take/keep a final cluster snapshot, and
          # (when not kept) delete the load/serve cluster parameter groups.
          "rds:DeleteDBInstance",
          "rds:CreateDBClusterSnapshot",
          "rds:DeleteDBClusterParameterGroup",
        ]
        # cluster + db + cluster-pg (the shared list), plus the cluster-snapshot the final
        # snapshot lands in. All name-scoped to gp-people-db-20*, so this can only ever touch a
        # dated loader cluster, never the serving cluster or shared infra.
        Resource = concat(local.loader_rds_cluster_arns, [
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster-snapshot:${local.loader_cluster_prefix}*",
        ])
      },
      {
        Sid      = "PassRdsS3ImportRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.rds_s3_import.arn
      },
      {
        Sid    = "RdsClusterEncryptionKey"
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
        ]
        Resource = local.loader_cluster_kms_key_arn
      },
    ]
  })
}
