#==============================================================================
# Optional sample log sources (web server, VPC flow logs, CloudTrail) streaming
# to the destination in the deployment region.
#==============================================================================
resource "terraform_data" "demo_preconditions" {
  count = var.deploy_demo ? 1 : 0

  lifecycle {
    precondition {
      condition     = contains(local.spoke_regions, local.region)
      error_message = "deploy_demo requires the deployment region (${local.region}) to be included in spoke_regions."
    }
    precondition {
      condition     = contains(var.spoke_accounts, local.account_id)
      error_message = "deploy_demo requires the primary account ID (${local.account_id}) to be included in spoke_accounts."
    }
  }
}

module "demo" {
  source = "./modules/demo"
  count  = var.deploy_demo ? 1 : 0

  name_prefix        = "${var.name_prefix}-Demo"
  availability_zones = local.azs
  account_id         = local.account_id
  destination_arn    = "arn:${local.partition}:logs:${local.region}:${local.account_id}:destination:${local.destination_name}"

  depends_on = [
    terraform_data.demo_preconditions,
    aws_cloudwatch_log_destination_policy.spoke,
    aws_opensearch_domain.es,
  ]
}
