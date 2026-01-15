locals {
  marts_config = yamldecode(file("${path.module}/config/marts.yaml"))
  marts        = local.marts_config.marts

  marts_map = { for mart in local.marts : mart.name => mart }
}
