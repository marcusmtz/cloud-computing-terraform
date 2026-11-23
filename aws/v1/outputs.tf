output "api_endpoint" {
  description = "Base HTTPS del API Gateway HTTP API."
  value       = aws_apigatewayv2_api.catalog.api_endpoint
}

output "database_endpoint" {
  description = "DNS privado de RDS; no es accesible desde Internet."
  value       = aws_db_instance.norcom.address
}

output "catalog_secret_arn" {
  description = "ARN del secreto lector escrito por el bootstrap."
  value       = aws_secretsmanager_secret.catalog_reader.arn
}

output "bootstrap_function_name" {
  description = "Lambda de inicialización manual; no tiene ruta HTTP."
  value       = aws_lambda_function.bootstrap.function_name
}

output "vpc_id" {
  description = "VPC en la que residen Lambda, endpoint y RDS."
  value       = module.network.vpc_id
}

output "managed_ad_dns_ip_addresses" {
  description = "Direcciones DNS privadas del AWS Managed Microsoft AD para configuración de clientes internos."
  value       = aws_directory_service_directory.norcom.dns_ip_addresses
}
