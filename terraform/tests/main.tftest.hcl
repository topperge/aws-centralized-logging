# Plan-only tests using mocked providers; no AWS credentials are required.
# Run with `terraform test` from the terraform/ directory.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "us-east-1" }
  }
  override_data {
    target = data.aws_regions.enabled
    values = { names = ["us-east-1", "us-east-2", "us-west-2"] }
  }
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
}

mock_provider "random" {}

variables {
  admin_email          = "admin@example.com"
  spoke_accounts       = ["111111111111", "222222222222"]
  spoke_regions        = ["us-east-1", "us-west-2"]
  transformer_zip_path = "tests/fixtures/transformer.txt"
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_opensearch_domain.es.cluster_config[0].instance_count == 4
    error_message = "Small cluster should have 4 data nodes"
  }
  assert {
    condition     = aws_opensearch_domain.es.cluster_config[0].instance_type == "r5.large.elasticsearch"
    error_message = "Small cluster should use r5.large data nodes"
  }
  assert {
    condition     = aws_opensearch_domain.es.cluster_config[0].dedicated_master_count == 3
    error_message = "Domain should have 3 dedicated master nodes"
  }
  assert {
    condition     = length(aws_subnet.isolated) == 2 && length(aws_subnet.public) == 2
    error_message = "Domain VPC should have 2 isolated and 2 public subnets"
  }
  assert {
    condition     = aws_subnet.isolated[0].cidr_block == "10.0.0.0/24" && aws_subnet.public[1].cidr_block == "10.0.3.0/24"
    error_message = "Unexpected subnet CIDRs"
  }
  assert {
    condition     = toset(keys(aws_cloudwatch_log_destination.spoke)) == toset(["us-east-1", "us-west-2"])
    error_message = "Destinations should be created in each spoke region"
  }
  assert {
    condition     = aws_kinesis_firehose_delivery_stream.logs.name == "CL-Firehose"
    error_message = "Firehose name must match the transformer's DELIVERY_STREAM"
  }
  assert {
    condition     = aws_lambda_function.transformer.environment[0].variables.DELIVERY_STREAM == aws_kinesis_firehose_delivery_stream.logs.name
    error_message = "Transformer must target the Firehose delivery stream"
  }
  assert {
    condition     = aws_cognito_user_pool.es.user_pool_tier == "PLUS"
    error_message = "ENFORCED advanced security requires the PLUS tier"
  }
  assert {
    condition     = aws_kms_key.alarms.enable_key_rotation && aws_kms_alias.alarms.name == "alias/CL-alarms"
    error_message = "Alarm topic should use a rotating customer-managed KMS key"
  }
  assert {
    condition     = length(aws_instance.jumpbox) == 0 && length(module.demo) == 0
    error_message = "Jumpbox and demo should not be deployed by default"
  }
}

run "all_regions" {
  command = plan

  variables {
    spoke_regions = ["All"]
  }

  assert {
    condition     = length(aws_cloudwatch_log_destination.spoke) == 3
    error_message = "\"All\" should expand to every enabled region"
  }
}

run "large_cluster" {
  command = plan

  variables {
    cluster_size = "Large"
  }

  assert {
    condition     = aws_opensearch_domain.es.cluster_config[0].instance_count == 6 && aws_opensearch_domain.es.cluster_config[0].instance_type == "r5.4xlarge.elasticsearch"
    error_message = "Large cluster should have 6 r5.4xlarge data nodes"
  }
}

run "jumpbox_and_demo" {
  command = plan

  # Pin the UUID so the destination name is known during plan.
  override_resource {
    target          = random_uuid.solution
    override_during = plan
    values          = { result = "00000000-0000-0000-0000-000000000000" }
  }

  variables {
    deploy_jumpbox = true
    jumpbox_key    = "my-key"
    deploy_demo    = true
  }

  assert {
    condition     = length(aws_instance.jumpbox) == 1 && aws_instance.jumpbox[0].metadata_options[0].http_tokens == "required"
    error_message = "Jumpbox should be deployed with IMDSv2"
  }
  assert {
    condition     = module.demo[0].destination_arn == "arn:aws:logs:us-east-1:111111111111:destination:CL-Destination-00000000-0000-0000-0000-000000000000"
    error_message = "Demo should stream to the destination in the deployment region"
  }
}

run "invalid_cluster_size" {
  command = plan

  variables {
    cluster_size = "Huge"
  }

  expect_failures = [var.cluster_size]
}

run "invalid_admin_email" {
  command = plan

  variables {
    admin_email = "not-an-email"
  }

  expect_failures = [var.admin_email]
}

run "invalid_spoke_region" {
  command = plan

  variables {
    spoke_regions = ["us-east-1", "mars-north-1"]
  }

  expect_failures = [aws_cloudwatch_log_destination.spoke]
}

run "jumpbox_requires_key" {
  command = plan

  variables {
    deploy_jumpbox = true
  }

  expect_failures = [aws_instance.jumpbox]
}

run "demo_requires_region_in_spokes" {
  command = plan

  variables {
    deploy_demo   = true
    spoke_regions = ["us-west-2"]
  }

  expect_failures = [terraform_data.demo_preconditions]
}

run "demo_requires_account_in_spokes" {
  command = plan

  variables {
    deploy_demo    = true
    spoke_accounts = ["222222222222"]
  }

  expect_failures = [terraform_data.demo_preconditions]
}
