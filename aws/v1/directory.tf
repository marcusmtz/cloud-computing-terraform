# AWS Managed Microsoft AD for Norcom employees and private DNS.
# Lifecycle protection prevents an accidental terraform destroy while this
# directory is in use. Remove it only after the user explicitly approves.
resource "aws_directory_service_directory" "norcom" {
  name        = var.ad_domain_name
  short_name  = "NORCOM"
  password    = var.ad_admin_password
  edition     = "Standard"
  type        = "MicrosoftAD"
  description = "Private employee directory for the Norcom academic lab."

  vpc_settings {
    vpc_id     = module.network.vpc_id
    subnet_ids = local.private_subnet_ids
  }

  tags = {
    Name        = "norcom-lab-managed-ad"
    Project     = var.project_name
    Environment = var.environment
  }

  lifecycle {
    prevent_destroy = true
  }
}
