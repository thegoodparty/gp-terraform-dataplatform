# Gold-match Bedrock access. The matcher pod runs as its Astro deployment's
# Astronomer-managed workload identity, a role in Astronomer's account we can
# trust but not edit, so the Bedrock grant sits on a role HERE that trusts that
# identity and the pod assumes it (the gp-people-rds-admin shape in
# loader_iam.tf); calls then authorize and bill as this account.

locals {
  # Both Bedrock clients pin us-east-1 (bedrock_clients/embedding.py and
  # structured.py); var.aws_region is the loader's us-west-2 and must not leak
  # in here. The global profile may serve a request from any region and AWS
  # evaluates the global leg against a region-less model ARN, so the Haiku
  # model's region is wildcarded (matching empty and any region alike).
  # Foundation-model ARNs are account-less; inference profiles are not.
  # Nova is the matcher's selectable alternate embedding model, granted now so
  # an embedding-model change needs no IAM round trip.
  gold_match_bedrock_region = "us-east-1"
  gold_match_bedrock_arns = [
    "arn:aws:bedrock:${local.gold_match_bedrock_region}:${data.aws_caller_identity.current.account_id}:inference-profile/global.anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:${local.gold_match_bedrock_region}::foundation-model/amazon.titan-embed-text-v2:0",
    "arn:aws:bedrock:${local.gold_match_bedrock_region}::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0",
  ]
}

resource "aws_iam_role" "gold_match_bedrock" {
  for_each = local.astro_workload_identities

  name        = "gold-match-bedrock-${each.key}"
  description = "Assumed by the gold-match daily pod on the ${each.key} Astro deployment to call Bedrock."
  tags        = { Project = "gold-match", Environment = each.key }

  # Trust policy shared with the loader and L2 roles (local.astro_assume_role_policy).
  assume_role_policy = local.astro_assume_role_policy[each.key]
}

# Converse authorizes against bedrock:InvokeModel too; the matcher streams
# nothing, so the streaming action is deliberately absent.
resource "aws_iam_role_policy" "gold_match_bedrock" {
  for_each = local.astro_workload_identities

  name = "gold-match-bedrock-invoke"
  role = aws_iam_role.gold_match_bedrock[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GoldMatchBedrockInvoke"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = local.gold_match_bedrock_arns
      },
    ]
  })
}
