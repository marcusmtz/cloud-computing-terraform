terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region              = "us-east-2"
  allowed_account_ids = [var.expected_aws_account_id]
  default_tags {
    tags = { Project = "norcom", Environment = "u2-activity", ManagedBy = "Terraform" }
  }
}

data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "isolated" {
  name        = "norcom-u2-ec2-activity-isolated"
  description = "Temporary credit activity; no inbound or outbound traffic."
  vpc_id      = data.aws_vpc.default.id
  ingress     = []
  egress      = []
}

resource "aws_instance" "activity" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.isolated.id]
  associate_public_ip_address = false
  monitoring                  = false

  credit_specification { cpu_credits = "standard" }
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }
  tags = { Name = "norcom-u2-ec2-activity-temporary" }
}

output "instance_id" { value = aws_instance.activity.id }
