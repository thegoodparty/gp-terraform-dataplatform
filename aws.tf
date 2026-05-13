# =============================================================================
# AWS Resources
# =============================================================================
# AWS-side identity plumbing that bridges Astro Airflow deployments to AWS
# IAM. The Astronomer OIDC provider declared here is referenced by roles in
# other repos (e.g. people-api) that Airflow DAGs assume via
# sts:AssumeRoleWithWebIdentity.

# Fetches the TLS cert chain from the OIDC issuer's well-known endpoint so
# we can pin the root-of-trust thumbprint.
data "tls_certificate" "astronomer_oidc" {
  url = var.astronomer_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "astronomer" {
  url             = var.astronomer_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.astronomer_oidc.certificates[0].sha1_fingerprint]

  tags = {
    ManagedBy = "terraform"
    Component = "astronomer-oidc"
  }
}
