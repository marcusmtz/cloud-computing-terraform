data "aws_ami" "windows_server_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
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

resource "aws_iam_role" "windows_server" {
  count = var.enable_windows_server ? 1 : 0
  name  = "${var.project_name}-${var.environment}-windows-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "windows_ssm" {
  count      = var.enable_windows_server ? 1 : 0
  role       = aws_iam_role.windows_server[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The Windows VSS requester needs EC2 snapshot permissions on its own instance.
# Keep the attachment in Terraform so a recreated domain controller can be
# protected before a later teardown. Snapshots themselves are created on demand.
resource "aws_iam_role_policy_attachment" "windows_vss_snapshot" {
  count      = var.enable_windows_server ? 1 : 0
  role       = aws_iam_role.windows_server[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSEC2VssSnapshotPolicy"
}

resource "aws_iam_instance_profile" "windows_server" {
  count = var.enable_windows_server ? 1 : 0
  name  = "${var.project_name}-${var.environment}-windows-server-profile"
  role  = aws_iam_role.windows_server[0].name
}

resource "aws_security_group" "windows_server" {
  count       = var.enable_windows_server ? 1 : 0
  name        = "${var.project_name}-${var.environment}-windows-server-sg"
  description = "No inbound ports; administer Windows Server with AWS Systems Manager Session Manager."
  vpc_id      = module.network.vpc_id

  ingress {
    description = "Private-only NORCOM authentication bridge, reachable only from this server security group."
    from_port   = 8181
    to_port     = 8181
    protocol    = "tcp"
    self        = true
  }

  dynamic "egress" {
    for_each = local.windows_egress_proxy_enforcement_active ? [] : [1]
    content {
      description = local.windows_egress_proxy_enabled ? "Direct HTTPS retained until the optional proxy clients are configured and verified." : "HTTPS for Systems Manager, Windows activation, and updates."
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "egress" {
    for_each = local.windows_egress_proxy_enabled ? [1] : []
    content {
      description     = "HTTP CONNECT through the private Squid proxy; enforced only after separate client validation."
      from_port       = 3128
      to_port         = 3128
      protocol        = "tcp"
      security_groups = [aws_security_group.windows_egress_proxy[0].id]
    }
  }

  egress {
    description = "DNS queries to the VPC resolver for Active Directory forwarding."
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Private TCP traffic from HCM to the local authentication bridge."
    from_port   = 8181
    to_port     = 8181
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS queries to the VPC resolver for Active Directory forwarding."
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project_name}-${var.environment}-windows-server-sg" }
}

resource "aws_instance" "windows_server" {
  count = var.enable_windows_server ? 1 : 0
  ami   = data.aws_ami.windows_server_2022.id
  # c7i-flex.large has 4 GiB and 2 vCPU, and is marked Free Tier eligible
  # in this account. t3.medium is rejected by the account's Free Tier launch guard.
  instance_type               = "c7i-flex.large"
  subnet_id                   = module.network.subnet_ids_by_tier.public_a
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.windows_server[0].id]
  iam_instance_profile        = aws_iam_instance_profile.windows_server[0].name
  monitoring                  = false
  ebs_optimized               = true
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 40
    encrypted             = true
    delete_on_termination = true
  }

  user_data_replace_on_change = false

  tags = {
    Name    = "${var.project_name}-${var.environment}-windows-ad-lab"
    Purpose = "Self-managed Windows Server for NORCOM directory demonstration"
  }

  # AWS publishes a newer AMI regularly. Do not replace the only domain
  # controller during an ordinary Terraform plan; refresh the image only in a
  # reviewed maintenance window with a tested AD recovery path.
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy_attachment.windows_ssm]
}

resource "aws_ssm_association" "windows_network_protection_audit" {
  count = var.enable_windows_server ? 1 : 0

  name             = "AWS-RunPowerShellScript"
  association_name = "${var.project_name}-${var.environment}-windows-network-protection-audit"
  parameters = {
    commands = <<-POWERSHELL
      $ErrorActionPreference = 'Stop'
      Set-MpPreference -AllowNetworkProtectionOnWinServer $true -AllowDatagramProcessingOnWinServer $false -EnableNetworkProtection AuditMode
      $mode = [int](Get-MpPreference).EnableNetworkProtection
      if ($mode -ne 2) { throw "Expected Defender Network Protection AuditMode (2), received $mode" }
      Write-Output 'NORCOM_NETWORK_PROTECTION_AUDIT_MODE=2'
    POWERSHELL
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_server[0].id]
  }

  wait_for_success_timeout_seconds = 300
}
