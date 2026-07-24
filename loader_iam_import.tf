# One-time import of the loader admin IAM that already exists (the role + rds-admin
# came from the omni Pulumi stack; loader-s3-ssm/loader-provision were hand-added to
# dev). Prod's loader-s3-ssm and loader-provision do NOT exist yet and are created by
# apply — they have no import block here.
#
# PRECONDITION: decommission the role in the omni Pulumi stacks BEFORE applying these
# imports (remove createRdsAdminRole and `pulumi state delete` the resource on the dev
# AND prod stacks), so the role is not owned by two tools at once.
#
# Remove this file after the first successful apply.

import {
  to = aws_iam_role.rds_admin["dev"]
  id = "gp-people-rds-admin-dev"
}

import {
  to = aws_iam_role.rds_admin["prod"]
  id = "gp-people-rds-admin-prod"
}

import {
  to = aws_iam_role_policy.rds_admin["dev"]
  id = "gp-people-rds-admin-dev:rds-admin"
}

import {
  to = aws_iam_role_policy.rds_admin["prod"]
  id = "gp-people-rds-admin-prod:rds-admin"
}

import {
  to = aws_iam_role_policy.loader_s3_ssm["dev"]
  id = "gp-people-rds-admin-dev:loader-s3-ssm"
}

import {
  to = aws_iam_role_policy.loader_provision["dev"]
  id = "gp-people-rds-admin-dev:loader-provision"
}
