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

resource "aws_security_group" "isolated" {
  name        = "norcom-u2-rds-activity-isolated"
  description = "Temporary database activity; no application connections."
  vpc_id      = data.aws_vpc.default.id
  ingress     = []
  egress      = []
}

resource "aws_db_subnet_group" "activity" {
  name       = "norcom-u2-rds-activity-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "activity" {
  identifier                   = "norcom-u2-rds-credit-temporary"
  engine                       = "postgres"
  instance_class               = "db.t4g.micro"
  allocated_storage            = 20
  max_allocated_storage        = 20
  storage_type                 = "gp3"
  storage_encrypted            = true
  db_name                      = "norcomdemo"
  username                     = "norcomadmin"
  manage_master_user_password  = true
  db_subnet_group_name         = aws_db_subnet_group.activity.name
  vpc_security_group_ids       = [aws_security_group.isolated.id]
  publicly_accessible          = false
  multi_az                     = false
  backup_retention_period      = 0
  skip_final_snapshot          = true
  delete_automated_backups     = true
  deletion_protection          = false
  auto_minor_version_upgrade   = true
  apply_immediately            = true
  performance_insights_enabled = false
  tags                         = { Name = "norcom-u2-rds-credit-temporary" }
}

output "db_identifier" { value = aws_db_instance.activity.identifier }
