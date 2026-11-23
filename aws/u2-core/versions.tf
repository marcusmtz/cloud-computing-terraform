terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  backend "local" {
    path = ".secure-state/terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_aws_account_id]

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "network" {
  source       = "./network"
  aws_region   = var.aws_region
  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
}
