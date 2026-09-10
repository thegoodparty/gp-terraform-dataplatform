# =============================================================================
# Gold-match Bedrock access
#
# The gold-match matcher runs as a Kubernetes pod on the Astro deployments and
# calls Bedrock (Titan embeddings, the Claude Haiku global inference profile).
# The grant sits on each deployment's Astronomer-managed workload identity
# role, which the pod carries via IRSA, so there are no keys to rotate.
#
# The roles are created by Astronomer (Deployment > Details > Advanced >
# Workload identity), live in this account, and are referenced BY NAME:
# recreating a deployment changes its role name, at which point this policy
# fails to apply until the map below is updated.
# =============================================================================

locals {
  astro_workload_identity_roles = {
    dev  = "astro-galactian-element-5125"
    prod = "astro-exothermic-astronaut-9119"
  }

  # The global inference profile may route a request across regions, so the
  # foundation-model resources are region-wildcarded; the model list, not the
  # region, is what bounds this grant. Foundation-model ARNs are account-less.
  # Nova is the matcher's selectable alternate embedding model, granted now so
  # an embedding-model change needs no IAM round trip.
  gold_match_bedrock_arns = [
    "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/global.anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
    "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
    "arn:aws:bedrock:*::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0",
  ]
}

# Converse authorizes against bedrock:InvokeModel too; the matcher streams
# nothing, so the streaming action is deliberately absent.
resource "aws_iam_role_policy" "astro_gold_match_bedrock" {
  for_each = local.astro_workload_identity_roles

  name = "gold-match-bedrock-invoke"
  role = each.value
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
