locals {
  # Load mart configuration from YAML
  marts_config = yamldecode(file("${path.module}/config/marts.yaml"))
  marts        = local.marts_config.marts

  # Create map for easier reference
  marts_map = { for mart in local.marts : mart.name => mart }
}
