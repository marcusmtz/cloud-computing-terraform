locals {
  windows_egress_proxy_enabled = var.enable_windows_server && var.enable_windows_egress_proxy
  windows_egress_proxy_enforcement_active = (
    local.windows_egress_proxy_enabled &&
    var.enforce_windows_egress_proxy &&
    var.windows_proxy_clients_configured
  )

  windows_egress_proxy_allowed_domains = distinct(concat([
    "ec2.${var.aws_region}.amazonaws.com",
    "ssm.${var.aws_region}.amazonaws.com",
    "ssmmessages.${var.aws_region}.amazonaws.com",
    "ec2messages.${var.aws_region}.amazonaws.com",
    "logs.${var.aws_region}.amazonaws.com",
    "monitoring.${var.aws_region}.amazonaws.com",
    "amazon-ssm-${var.aws_region}.s3.${var.aws_region}.amazonaws.com",
    "${var.aws_region}-birdwatcher-prod.s3.${var.aws_region}.amazonaws.com",
    "aws-windows-downloads-${var.aws_region}.s3.${var.aws_region}.amazonaws.com",
  ], var.windows_egress_proxy_allowed_domains))
}

data "aws_ami" "amazon_linux_2023_proxy" {
  count       = local.windows_egress_proxy_enabled ? 1 : 0
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_iam_role" "windows_egress_proxy" {
  count = local.windows_egress_proxy_enabled ? 1 : 0
  name  = "${var.project_name}-${var.environment}-windows-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "windows_egress_proxy_ssm" {
  count      = local.windows_egress_proxy_enabled ? 1 : 0
  role       = aws_iam_role.windows_egress_proxy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "windows_egress_proxy" {
  count = local.windows_egress_proxy_enabled ? 1 : 0
  name  = "${var.project_name}-${var.environment}-windows-proxy-profile"
  role  = aws_iam_role.windows_egress_proxy[0].name
}

resource "aws_security_group" "windows_egress_proxy" {
  count       = local.windows_egress_proxy_enabled ? 1 : 0
  name        = "${var.project_name}-${var.environment}-windows-proxy-sg"
  description = "Private HTTP proxy for the Windows Server; ingress is limited to the public-a subnet CIDR."
  vpc_id      = module.network.vpc_id

  egress {
    description = "HTTP package repositories and Windows Update downloads. Squid applies the hostname allowlist for Windows clients."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS for AWS endpoints, Azure Relay, and Microsoft updates. Squid applies the hostname allowlist for Windows clients."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS to the VPC resolver."
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "TCP DNS to the VPC resolver."
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project_name}-${var.environment}-windows-proxy-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "windows_to_egress_proxy" {
  count = local.windows_egress_proxy_enabled ? 1 : 0

  security_group_id            = aws_security_group.windows_egress_proxy[0].id
  referenced_security_group_id = aws_security_group.windows_server[0].id
  from_port                    = 3128
  to_port                      = 3128
  ip_protocol                  = "tcp"
  description                  = "Squid proxy from the NORCOM Windows Server security group only."
}

resource "aws_instance" "windows_egress_proxy" {
  count         = local.windows_egress_proxy_enabled ? 1 : 0
  ami           = data.aws_ami.amazon_linux_2023_proxy[0].id
  instance_type = var.windows_egress_proxy_instance_type
  subnet_id     = module.network.subnet_ids_by_tier.public_a
  # Keep the private address stable so Windows SSM Agent can reconnect after a proxy replacement.
  private_ip                  = "10.42.12.181"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.windows_egress_proxy[0].id]
  iam_instance_profile        = aws_iam_instance_profile.windows_egress_proxy[0].name
  monitoring                  = false
  ebs_optimized               = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/squid-user-data.sh.tftpl", {
    allowed_domains = join(" ", local.windows_egress_proxy_allowed_domains)
  })
  # User data remains the bootstrap path for a new instance. Existing proxy
  # updates are applied through the managed SSM association below, so editing
  # the allowlist does not replace the live EC2 instance.
  user_data_replace_on_change = false

  tags = {
    Name      = "${var.project_name}-${var.environment}-windows-egress-proxy"
    Purpose   = "Allowlisted HTTPS egress for NORCOM Windows Server demonstration"
    Component = "windows-egress-proxy"
  }

  # Refreshing the public AMI must not replace the active proxy during an
  # ordinary Apply; update it only in a reviewed maintenance window.
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy_attachment.windows_egress_proxy_ssm]
}
