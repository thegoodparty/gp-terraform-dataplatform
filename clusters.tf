# Always-on single-node classic cluster for gp-api's reads, running alongside
# wh-gp-api so the app can be pointed at either one while we compare them.
#
# Why classic rather than serverless: wh-gp-api auto-stops after two minutes, so
# roughly 200 queries a day pay about 2.8 seconds of warehouse start and land
# near 8 seconds end to end against a 400 ms baseline. Holding a serverless
# warehouse warm around the clock costs more than the app can justify. Classic
# compute bills EC2 in our own VPC plus all-purpose DBUs, which is cheap enough
# to leave running, so the cold start disappears by construction.
#
# Why one small node: a day of query history shows the workload barely uses the
# compute it already has. Execution is 6% of wall clock, no query has ever
# spilled, and the median query that actually runs keeps half a core busy. Even
# across the heaviest scans the p95 keeps under seven cores busy.
#
# The real risk is concurrency rather than size. Peak overlap is 27 queries and
# about 220 queries a day already queue for a second serverless cluster. This
# cluster cannot scale out at all, so if queueing rather than cold start is what
# users feel, this will be worse. Measuring that is the point of the experiment.
resource "databricks_cluster" "gp_api_serving" {
  cluster_name  = local.gp_api.cluster_name
  spark_version = "16.4.x-scala2.12"
  node_type_id  = var.gp_api_cluster_node_type
  num_workers   = 0

  runtime_engine = var.gp_api_cluster_photon ? "PHOTON" : "STANDARD"

  # Staying warm is the whole experiment, so never auto-terminate. Pinning also
  # keeps the cluster out of the inactive-cluster reaper.
  autotermination_minutes = 0
  is_pinned               = true

  # Unity Catalog reads by a service principal over JDBC need shared access mode.
  # SINGLE_USER would tie the cluster to one identity.
  data_security_mode = "USER_ISOLATION"

  spark_conf = {
    "spark.databricks.cluster.profile" = "singleNode"
    "spark.master"                     = "local[*]"

    # wh-gp-api picks up ansi_mode from the workspace SQL config, which clusters
    # do not read. Without this the same query can behave differently depending
    # on which compute gp-api is pointed at, which would confuse the comparison.
    "spark.sql.ansi.enabled" = "true"
  }

  custom_tags = {
    ResourceClass = "SingleNode" # required for a zero-worker cluster
    product       = "gp_api"
    purpose       = "app_serving"
  }

  aws_attributes {
    # On demand rather than spot: a reclaimed spot node restarts the cluster and
    # brings back the cold start this is meant to remove.
    availability = "ON_DEMAND"

    # Pinned to a workspace subnet AZ. Both private subnets have thousands of
    # free addresses, so a single node has no placement pressure either way.
    zone_id = "us-west-2a"
  }

  # The node families this cluster is sized for ship local NVMe, which the disk
  # cache uses. That cache serves 83% of the bytes read by queries that miss the
  # result cache, so it matters more here than autoscaling EBS would.
  enable_elastic_disk = false
}
