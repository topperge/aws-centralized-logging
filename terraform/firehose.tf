#==============================================================================
# Kinesis Data Firehose -> Elasticsearch (all documents backed up to S3)
#==============================================================================
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${local.firehose_name}"
  retention_in_days = 365
}

resource "aws_cloudwatch_log_stream" "firehose_es" {
  name           = "ElasticsearchDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_cloudwatch_log_stream" "firehose_s3" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name_prefix        = "${var.name_prefix}-Firehose-"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

data "aws_iam_policy_document" "firehose" {
  statement {
    sid = "S3Access"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [aws_s3_bucket.firehose.arn, "${aws_s3_bucket.firehose.arn}/*"]
  }
  statement {
    sid       = "S3Kms"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["arn:${local.partition}:kms:${local.region}:${local.account_id}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["${aws_s3_bucket.firehose.arn}/*"]
    }
  }
  statement {
    sid = "DomainVpc"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNetworkInterfaces",
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]
  }
  statement {
    sid = "Domain"
    actions = [
      "es:DescribeElasticsearchDomain",
      "es:DescribeElasticsearchDomains",
      "es:DescribeElasticsearchDomainConfig",
      "es:ESHttpPost",
      "es:ESHttpPut",
    ]
    resources = [local.domain_arn, "${local.domain_arn}/*"]
  }
  statement {
    sid     = "DomainHttpGet"
    actions = ["es:ESHttpGet"]
    resources = [
      "${local.domain_arn}/_all/_settings",
      "${local.domain_arn}/_cluster/stats",
      "${local.domain_arn}/cwl-kinesis/_mapping/kinesis",
      "${local.domain_arn}/_nodes",
      "${local.domain_arn}/_nodes/*/stats",
      "${local.domain_arn}/_stats",
      "${local.domain_arn}/cwl-kinesis/_stats",
    ]
  }
  statement {
    sid       = "DeliveryLogs"
    actions   = ["logs:PutLogEvents", "logs:CreateLogStream"]
    resources = [aws_cloudwatch_log_group.firehose.arn, "${aws_cloudwatch_log_group.firehose.arn}:*"]
  }
  statement {
    sid       = "KinesisKms"
    actions   = ["kms:Decrypt"]
    resources = ["arn:${local.partition}:kms:${local.region}:${local.account_id}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["kinesis.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:kinesis:arn"
      values   = [aws_kinesis_stream.logs.arn]
    }
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "${var.name_prefix}-Firehose-Policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_kinesis_firehose_delivery_stream" "logs" {
  name        = local.firehose_name
  destination = "elasticsearch"

  server_side_encryption {
    enabled  = true
    key_type = "AWS_OWNED_CMK"
  }

  elasticsearch_configuration {
    domain_arn            = aws_opensearch_domain.es.arn
    role_arn              = aws_iam_role.firehose.arn
    index_name            = "cwl"
    index_rotation_period = "OneDay"
    s3_backup_mode        = "AllDocuments"

    s3_configuration {
      bucket_arn = aws_s3_bucket.firehose.arn
      role_arn   = aws_iam_role.firehose.arn

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose.name
        log_stream_name = aws_cloudwatch_log_stream.firehose_s3.name
      }
    }

    vpc_config {
      role_arn           = aws_iam_role.firehose.arn
      subnet_ids         = aws_subnet.isolated[*].id
      security_group_ids = [aws_security_group.es.id]
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_es.name
    }
  }

  depends_on = [aws_iam_role_policy.firehose, aws_s3_bucket_policy.firehose]
}
