#==============================================================================
# Domain VPC: 2 isolated subnets (domain + Firehose ENIs) and 2 public subnets
# (jumpbox), with VPC flow logs to CloudWatch Logs.
#==============================================================================
resource "aws_vpc" "es" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-ESVPC" }
}

resource "aws_subnet" "isolated" {
  count = length(local.azs)

  vpc_id            = aws_vpc.es.id
  cidr_block        = cidrsubnet(aws_vpc.es.cidr_block, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name_prefix}-ESIsolatedSubnet${count.index + 1}" }
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.es.id
  cidr_block              = cidrsubnet(aws_vpc.es.cidr_block, 8, count.index + length(local.azs))
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-ESPublicSubnet${count.index + 1}" }
}

resource "aws_internet_gateway" "es" {
  vpc_id = aws_vpc.es.id

  tags = { Name = "${var.name_prefix}-ESVPC" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.es.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.es.id
  }

  tags = { Name = "${var.name_prefix}-ESPublic" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.es.id

  tags = { Name = "${var.name_prefix}-ESIsolated" }
}

resource "aws_route_table_association" "isolated" {
  count = length(aws_subnet.isolated)

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}

#------------------------------------------------------------------------------
# VPC flow logs
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name_prefix = "${var.name_prefix}-ESVPCFlowLogs-"
}

data "aws_iam_policy_document" "vpc_flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow" {
  name_prefix        = "${var.name_prefix}-ESVPCFlow-"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_assume.json
}

data "aws_iam_policy_document" "vpc_flow" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = [aws_cloudwatch_log_group.vpc_flow.arn, "${aws_cloudwatch_log_group.vpc_flow.arn}:*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.vpc_flow.arn]
  }
}

resource "aws_iam_role_policy" "vpc_flow" {
  role   = aws_iam_role.vpc_flow.id
  policy = data.aws_iam_policy_document.vpc_flow.json
}

resource "aws_flow_log" "es" {
  vpc_id          = aws_vpc.es.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.vpc_flow.arn
  iam_role_arn    = aws_iam_role.vpc_flow.arn
}

#------------------------------------------------------------------------------
# Domain security group
#------------------------------------------------------------------------------
resource "aws_security_group" "es" {
  name_prefix = "${var.name_prefix}-ESSG-"
  description = "Centralized Logging domain and Firehose ENIs"
  vpc_id      = aws_vpc.es.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "es_https" {
  security_group_id = aws_security_group.es.id
  description       = "allow inbound https traffic"
  cidr_ipv4         = aws_vpc.es.cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "es_https" {
  security_group_id = aws_security_group.es.id
  description       = "allow outbound https"
  cidr_ipv4         = aws_vpc.es.cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
