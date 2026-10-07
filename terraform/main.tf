data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Regions enabled (opted in) for this account; used to expand spoke_regions = ["All"].
data "aws_regions" "enabled" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Replaces the Custom::CreateUUID helper Lambda custom resource.
resource "random_uuid" "solution" {}

locals {
  solution_id      = "SO0009"
  solution_name    = "Centralized Logging on AWS"
  solution_version = "v4.0.6"
  metrics_endpoint = "https://metrics.awssolutionsbuilder.com/generic"

  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  uuid             = random_uuid.solution.result
  firehose_name    = "${var.name_prefix}-Firehose"
  destination_name = "${var.name_prefix}-Destination-${local.uuid}"
  azs              = slice(data.aws_availability_zones.available.names, 0, 2)

  spoke_regions = var.spoke_regions[0] == "All" ? sort(tolist(data.aws_regions.enabled.names)) : var.spoke_regions

  es_cluster = {
    Small  = { node_count = 4, master_type = "c5.large.elasticsearch", instance_type = "r5.large.elasticsearch" }
    Medium = { node_count = 6, master_type = "c5.large.elasticsearch", instance_type = "r5.2xlarge.elasticsearch" }
    Large  = { node_count = 6, master_type = "c5.large.elasticsearch", instance_type = "r5.4xlarge.elasticsearch" }
  }[var.cluster_size]
  es_master_count = 3

  domain_arn = "arn:${local.partition}:es:${local.region}:${local.account_id}:domain/${var.domain_name}"
}
