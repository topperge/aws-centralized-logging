#==============================================================================
# Elasticsearch / OpenSearch domain
#==============================================================================

# Replaces the Custom::CreateESServiceRole helper Lambda custom resource.
resource "aws_iam_service_linked_role" "es" {
  count            = var.create_es_service_linked_role ? 1 : 0
  aws_service_name = "es.amazonaws.com"
}

data "aws_iam_policy_document" "es_access" {
  statement {
    actions = [
      "es:ESHttpGet",
      "es:ESHttpDelete",
      "es:ESHttpPut",
      "es:ESHttpPost",
      "es:ESHttpHead",
      "es:ESHttpPatch",
    ]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.cognito_auth.arn]
    }
    resources = ["${local.domain_arn}/*"]
  }
  statement {
    actions = [
      "es:DescribeElasticsearchDomain",
      "es:DescribeElasticsearchDomains",
      "es:DescribeElasticsearchDomainConfig",
      "es:ESHttpPost",
      "es:ESHttpPut",
      "es:HttpGet",
    ]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.firehose.arn]
    }
    resources = ["${local.domain_arn}/*"]
  }
}

resource "aws_opensearch_domain" "es" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type            = local.es_cluster.instance_type
    instance_count           = local.es_cluster.node_count
    dedicated_master_enabled = true
    dedicated_master_type    = local.es_cluster.master_type
    dedicated_master_count   = local.es_master_count
    zone_awareness_enabled   = true

    zone_awareness_config {
      availability_zone_count = 2
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.ebs_volume_size
    volume_type = "gp2"
  }

  vpc_options {
    subnet_ids         = aws_subnet.isolated[*].id
    security_group_ids = [aws_security_group.es.id]
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  snapshot_options {
    automated_snapshot_start_hour = 0
  }

  cognito_options {
    enabled          = true
    user_pool_id     = aws_cognito_user_pool.es.id
    identity_pool_id = aws_cognito_identity_pool.es.id
    role_arn         = aws_iam_role.es_cognito.arn
  }

  access_policies = data.aws_iam_policy_document.es_access.json

  depends_on = [
    aws_iam_service_linked_role.es,
    aws_cognito_user_pool_domain.es,
    aws_iam_role_policy.es_cognito,
  ]
}
