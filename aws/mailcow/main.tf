locals {
  # The assessed demo covers internal mailbox exchange. Public SMTP delivery is out of scope.
  public_ports       = merge({ http = 80, https = 443 }, var.enable_public_smtp_receive ? { smtp = 25 } : {})
  client_ports       = var.enable_mail_clients ? { submission = 587, imaps = 993 } : {}
  outbound_web_ports = { http = 80, https = 443 }
}

data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "mail" {
  key_name   = "norcom-mail-lab-admin"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "mail" {
  name        = "norcom-roundcube-lab"
  description = "Roundcube, Postfix and Dovecot mail lab"
  vpc_id      = var.vpc_id


  tags = { Name = "norcom-roundcube-lab" }
}

resource "aws_vpc_security_group_ingress_rule" "public_mail" {
  for_each          = merge(local.public_ports, local.client_ports)
  security_group_id = aws_security_group.mail.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
  description       = "Mail lab ${each.key}"
}

resource "aws_vpc_security_group_egress_rule" "web_updates" {
  for_each          = local.outbound_web_ports
  security_group_id = aws_security_group.mail.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
  description       = "Outbound HTTP/HTTPS for OS updates, certificate renewal, and SSM management."
}

resource "aws_instance" "mail" {
  ami                    = data.aws_ami.ubuntu_arm.id
  instance_type          = "t3.small"
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.mail.id]
  key_name               = aws_key_pair.mail.key_name
  iam_instance_profile   = aws_iam_instance_profile.mail.name
  user_data = templatefile("${path.module}/cloud-init.sh", {
    mail_domain   = var.mail_domain
    mail_hostname = "mail.${var.mail_domain}"
    contact_email = var.contact_email
  })
  user_data_replace_on_change = false
  # Keep the running demo stable when Canonical publishes a newer AMI. New
  # instances still use the latest matching image; upgrades are an explicit rollout.
  lifecycle {
    ignore_changes = [user_data, ami]
  }
  monitoring = false

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "norcom-roundcube-lab" }
}

resource "aws_iam_role" "mail" {
  name = "norcom-roundcube-lab-ssm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "norcom-roundcube-lab-ssm" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.mail.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "mail" {
  name = "norcom-roundcube-lab-ssm"
  role = aws_iam_role.mail.name
}

resource "aws_eip" "mail" {
  domain = "vpc"
  tags   = { Name = "norcom-roundcube-lab" }
}

resource "aws_eip_association" "mail" {
  instance_id   = aws_instance.mail.id
  allocation_id = aws_eip.mail.id
}
