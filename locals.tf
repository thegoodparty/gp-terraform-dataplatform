locals {
  marts_config = yamldecode(file("${path.module}/config/marts.yaml"))
  marts        = local.marts_config.marts

  marts_map = { for mart in local.marts : mart.name => mart }

  # Merge Astro environments from separate variables
  astro_environments = merge(
    var.astro_env_dev != null ? { dev = var.astro_env_dev } : {},
    var.astro_env_prod != null ? { prod = var.astro_env_prod } : {}
  )
}
