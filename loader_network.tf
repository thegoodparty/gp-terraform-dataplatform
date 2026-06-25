# =============================================================================
# People-API loader networking — S3 Gateway VPC endpoint (DATA-1640)
#
# Aurora's `copy` step (aws_s3.table_import_from_s3) reads the unloaded CSVs from S3. Without
# a Gateway endpoint, that traffic egresses through the NAT gateway — bandwidth-limited and
# costly at ~361 GB per refresh. This adds the S3 service to the VPC's route tables so the
# reads stay on the AWS backbone. The TDD flags the endpoint as missing (Network section), and
# DATA-1856 (networking prerequisites) did not include it.
#
# Gated on loader_vpc_id so `terraform plan` is a no-op until the prod VPC id is supplied
# (tfvars). The endpoint associates with every route table in that VPC, which is standard for
# an S3 gateway endpoint; scope to specific route tables if a narrower blast radius is wanted.
# Verify no S3 gateway endpoint already exists on the VPC before applying — a route table can
# associate with only one.
# =============================================================================

variable "loader_vpc_id" {
  description = "Prod VPC id hosting the loader's Aurora clusters. Empty disables the S3 gateway endpoint."
  type        = string
  default     = ""
}

data "aws_route_tables" "loader_vpc" {
  count  = var.loader_vpc_id != "" ? 1 : 0
  vpc_id = var.loader_vpc_id
}

resource "aws_vpc_endpoint" "loader_s3" {
  count             = var.loader_vpc_id != "" ? 1 : 0
  vpc_id            = var.loader_vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.loader_vpc[0].ids

  # Project/ManagedBy come from the provider default_tags.
  tags = {
    Name = "people-loader-s3"
  }
}
