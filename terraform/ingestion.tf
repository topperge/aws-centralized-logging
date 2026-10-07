#==============================================================================
# Kinesis data stream -> transformer Lambda -> Firehose
#==============================================================================
resource "aws_kinesis_stream" "logs" {
  name             = "${var.name_prefix}-KinesisStream"
  shard_count      = 1
  retention_period = 24
  encryption_type  = "KMS"
  kms_key_id       = "alias/aws/kinesis"

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

resource "aws_sqs_queue" "transformer_dlq" {
  name              = "${var.name_prefix}-Transformer-DLQ"
  kms_master_key_id = "alias/aws/sqs"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transformer" {
  name_prefix        = "${var.name_prefix}-Transformer-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "transformer_basic" {
  role       = aws_iam_role.transformer.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "transformer" {
  statement {
    sid = "ReadDataStream"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard",
    ]
    resources = [aws_kinesis_stream.logs.arn]
  }
  statement {
    sid       = "ListStreams"
    actions   = ["kinesis:ListStreams"]
    resources = ["*"]
  }
  statement {
    sid       = "DeadLetterQueue"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.transformer_dlq.arn]
  }
  statement {
    sid       = "PutToFirehose"
    actions   = ["firehose:PutRecordBatch"]
    resources = [aws_kinesis_firehose_delivery_stream.logs.arn]
  }
}

resource "aws_iam_role_policy" "transformer" {
  role   = aws_iam_role.transformer.id
  policy = data.aws_iam_policy_document.transformer.json
}

resource "aws_lambda_function" "transformer" {
  function_name    = "${var.name_prefix}-Transformer"
  description      = "${local.solution_name} - Lambda function to transform log events and send to kinesis firehose"
  role             = aws_iam_role.transformer.arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  timeout          = 300
  filename         = var.transformer_zip_path
  source_code_hash = filebase64sha256(var.transformer_zip_path)

  dead_letter_config {
    target_arn = aws_sqs_queue.transformer_dlq.arn
  }

  environment {
    variables = {
      LOG_LEVEL             = var.lambda_log_level
      SOLUTION_ID           = local.solution_id
      SOLUTION_VERSION      = local.solution_version
      UUID                  = local.uuid
      CLUSTER_SIZE          = var.cluster_size
      DELIVERY_STREAM       = local.firehose_name
      METRICS_ENDPOINT      = local.metrics_endpoint
      SEND_METRIC           = var.send_anonymized_metrics ? "Yes" : "No"
      CUSTOM_SDK_USER_AGENT = "AwsSolution/${local.solution_id}/${local.solution_version}"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.transformer_basic,
    aws_iam_role_policy.transformer,
  ]
}

resource "aws_lambda_event_source_mapping" "transformer" {
  event_source_arn  = aws_kinesis_stream.logs.arn
  function_name     = aws_lambda_function.transformer.arn
  starting_position = "TRIM_HORIZON"
  batch_size        = 100
}

#------------------------------------------------------------------------------
# Error alarm
#------------------------------------------------------------------------------
# Customer-managed key for the alarm topic. CloudWatch alarms cannot publish to
# topics encrypted with the AWS-managed aws/sns key, because its key policy
# cannot be changed to grant cloudwatch.amazonaws.com access.
data "aws_iam_policy_document" "alarms_key" {
  statement {
    sid       = "EnableAccountPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
  statement {
    sid       = "AllowCloudWatchAlarms"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:*"]
    }
  }
}

resource "aws_kms_key" "alarms" {
  description         = "${local.solution_name} - encryption for the ${var.name_prefix} Lambda error alarm topic"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.alarms_key.json
}

resource "aws_kms_alias" "alarms" {
  name          = "alias/${var.name_prefix}-alarms"
  target_key_id = aws_kms_key.alarms.key_id
}

resource "aws_sns_topic" "alarms" {
  name              = "${var.name_prefix}-Lambda-Error"
  display_name      = "CL-Lambda-Error"
  kms_master_key_id = aws_kms_key.alarms.arn
}

resource "aws_sns_topic_subscription" "admin_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

resource "aws_cloudwatch_metric_alarm" "transformer_errors" {
  alarm_name          = "${var.name_prefix}-LambdaError-Alarm"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.transformer.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0.05
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}
