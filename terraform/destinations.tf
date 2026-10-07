#==============================================================================
# CloudWatch Logs destinations in every spoke region, all targeting the central
# Kinesis data stream. Replaces the Custom::CWDestination helper Lambda custom
# resource; uses the AWS provider v6 per-resource `region` argument.
#==============================================================================
data "aws_iam_policy_document" "cw_destination_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cw_destination" {
  name_prefix        = "${var.name_prefix}-CWDestination-"
  assume_role_policy = data.aws_iam_policy_document.cw_destination_assume.json
}

data "aws_iam_policy_document" "cw_destination" {
  statement {
    actions   = ["kinesis:PutRecord"]
    resources = [aws_kinesis_stream.logs.arn]
  }
}

resource "aws_iam_role_policy" "cw_destination" {
  role   = aws_iam_role.cw_destination.id
  policy = data.aws_iam_policy_document.cw_destination.json
}

resource "aws_cloudwatch_log_destination" "spoke" {
  for_each = toset(local.spoke_regions)

  region     = each.key
  name       = local.destination_name
  role_arn   = aws_iam_role.cw_destination.arn
  target_arn = aws_kinesis_stream.logs.arn

  lifecycle {
    precondition {
      condition     = contains(data.aws_regions.enabled.names, each.key)
      error_message = "Spoke region ${each.key} is not a valid region enabled for this account."
    }
  }

  depends_on = [aws_iam_role_policy.cw_destination]
}

data "aws_iam_policy_document" "cw_destination_access" {
  for_each = aws_cloudwatch_log_destination.spoke

  statement {
    sid     = "AllowSpokesSubscribe"
    actions = ["logs:PutSubscriptionFilter"]
    principals {
      type        = "AWS"
      identifiers = var.spoke_accounts
    }
    resources = [each.value.arn]
  }
}

resource "aws_cloudwatch_log_destination_policy" "spoke" {
  for_each = aws_cloudwatch_log_destination.spoke

  region           = each.key
  destination_name = each.value.name
  access_policy    = data.aws_iam_policy_document.cw_destination_access[each.key].json
}
