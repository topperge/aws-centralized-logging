locals {
  filter_patterns = {
    Common         = "[host, ident, authuser, date, request, status, bytes, referrer, agent]"
    CloudTrail     = ""
    FlowLogs       = "[version, account_id, interface_id, srcaddr != \"-\", dstaddr != \"-\", srcport != \"-\", dstport != \"-\", protocol, packets, bytes, start, end, action, log_status]"
    Lambda         = "[timestamp=*Z, request_id=\"*-*\", event]"
    SpaceDelimited = "[]"
    Other          = ""
  }
}

#==============================================================================
# Demo VPC with 2 public subnets
#==============================================================================
resource "aws_vpc" "demo" {
  cidr_block           = "10.0.1.0/26"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-VPC" }
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.demo.id
  cidr_block              = cidrsubnet(aws_vpc.demo.cidr_block, 2, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-PublicSubnet${count.index + 1}" }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = { Name = "${var.name_prefix}-VPC" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = { Name = "${var.name_prefix}-Public" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#==============================================================================
# VPC flow logs
#==============================================================================
resource "aws_cloudwatch_log_group" "flow" {
  name_prefix       = "${var.name_prefix}-VPCFlowLogs-"
  retention_in_days = 7
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow" {
  name_prefix        = "${var.name_prefix}-VPCFlow-"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
}

data "aws_iam_policy_document" "flow" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = [aws_cloudwatch_log_group.flow.arn, "${aws_cloudwatch_log_group.flow.arn}:*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.flow.arn]
  }
}

resource "aws_iam_role_policy" "flow" {
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow.json
}

resource "aws_flow_log" "demo" {
  vpc_id          = aws_vpc.demo.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow.arn
  iam_role_arn    = aws_iam_role.flow.arn
}

resource "aws_cloudwatch_log_subscription_filter" "flow" {
  name            = "FlowLogSubscription"
  log_group_name  = aws_cloudwatch_log_group.flow.name
  filter_pattern  = local.filter_patterns.FlowLogs
  destination_arn = var.destination_arn
}

#==============================================================================
# Web server (Apache + PHP) shipping access logs via the CloudWatch agent
#==============================================================================
data "aws_ssm_parameter" "al2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_security_group" "web" {
  name_prefix = "${var.name_prefix}-WebSG-"
  description = "Centralized Logging demo web server"
  vpc_id      = aws_vpc.demo.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  security_group_id = aws_security_group.web.id
  description       = "allow HTTP traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "Allow all outbound traffic by default"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_cloudwatch_log_group" "web" {
  name_prefix       = "${var.name_prefix}-WebServer-"
  retention_in_days = 7
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name_prefix        = "${var.name_prefix}-WebServer-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "web" {
  statement {
    sid       = "LogWrite"
    actions   = ["logs:Create*", "logs:PutLogEvents"]
    resources = [aws_cloudwatch_log_group.web.arn, "${aws_cloudwatch_log_group.web.arn}:*"]
  }
}

resource "aws_iam_role_policy" "web" {
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.web.json
}

resource "aws_iam_instance_profile" "web" {
  name_prefix = "${var.name_prefix}-WebServer-"
  role        = aws_iam_role.web.name
}

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data = templatefile("${path.module}/templates/webserver-user-data.sh.tftpl", {
    log_group_name = aws_cloudwatch_log_group.web.name
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.name_prefix}-WebServer" }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy.web, aws_route_table_association.public]
}

resource "aws_cloudwatch_log_subscription_filter" "web" {
  name            = "WebServerSubscription"
  log_group_name  = aws_cloudwatch_log_group.web.name
  filter_pattern  = local.filter_patterns.Common
  destination_arn = var.destination_arn
}

#==============================================================================
# CloudTrail
#==============================================================================
resource "aws_cloudwatch_log_group" "trail" {
  name_prefix       = "${var.name_prefix}-CloudTrail-"
  retention_in_days = 7
}

resource "aws_s3_bucket" "trail" {
  bucket_prefix = "${lower(var.name_prefix)}-trail-"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid     = "EnforceSSL"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid     = "CloudTrailRead"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.trail.arn]
  }
  statement {
    sid     = "CloudTrailWrite"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${var.account_id}/*"]
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trail_logs" {
  name_prefix        = "${var.name_prefix}-TrailLogs-"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume.json
}

data "aws_iam_policy_document" "trail_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "trail_logs" {
  role   = aws_iam_role.trail_logs.id
  policy = data.aws_iam_policy_document.trail_logs.json
}

resource "aws_cloudtrail" "demo" {
  name                          = "${var.name_prefix}-Trail"
  s3_bucket_name                = aws_s3_bucket.trail.id
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_logs.arn
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_logs]
}

resource "aws_cloudwatch_log_subscription_filter" "trail" {
  name            = "CloudTrailSubscription"
  log_group_name  = aws_cloudwatch_log_group.trail.name
  filter_pattern  = local.filter_patterns.CloudTrail
  destination_arn = var.destination_arn
}
