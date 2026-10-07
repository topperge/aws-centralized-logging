#==============================================================================
# Optional Windows jumpbox for reaching Kibana inside the VPC
#==============================================================================
data "aws_ssm_parameter" "windows_ami" {
  count = var.deploy_jumpbox ? 1 : 0
  name  = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-Base"
}

resource "aws_security_group" "jumpbox" {
  count = var.deploy_jumpbox ? 1 : 0

  name_prefix = "${var.name_prefix}-JumpboxSG-"
  description = "Centralized Logging jumpbox"
  vpc_id      = aws_vpc.es.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "jumpbox" {
  for_each = var.deploy_jumpbox ? { http = 80, https = 443 } : {}

  security_group_id = aws_security_group.jumpbox[0].id
  description       = "allow outbound ${each.key}"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
}

resource "aws_instance" "jumpbox" {
  count = var.deploy_jumpbox ? 1 : 0

  ami                    = data.aws_ssm_parameter.windows_ami[0].value
  instance_type          = var.jumpbox_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jumpbox[0].id]
  key_name               = var.jumpbox_key

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.name_prefix}-Jumpbox" }

  lifecycle {
    ignore_changes = [ami]

    precondition {
      condition     = var.jumpbox_key != ""
      error_message = "jumpbox_key must be set when deploy_jumpbox is true."
    }
  }
}
