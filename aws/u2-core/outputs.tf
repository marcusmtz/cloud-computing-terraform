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

output "erp_function_name" {
  description = "Función privada que valida sesión, identidad y rol antes de atender el ERP."
  value       = aws_lambda_function.erp.function_name
}

output "vpc_id" {
  description = "VPC en la que residen Lambda, endpoint y RDS."
  value       = module.network.vpc_id
}

output "public_subnet_id" {
  description = "Subred pública A para servicios complementarios del laboratorio."
  value       = module.network.subnet_ids_by_tier.public_a
}

output "ops_alerts_topic_arn" {
  description = "Tema SNS para alarmas del núcleo y módulos complementarios de NORCOM U2."
  value       = aws_sns_topic.ops_alerts.arn
}

output "windows_server_instance_id" {
  description = "ID de la EC2 Windows Server opcional; null si no se habilitó."
  value       = var.enable_windows_server ? aws_instance.windows_server[0].id : null
}

output "windows_server_private_ip" {
  description = "IP privada del servidor Windows opcional."
  value       = var.enable_windows_server ? aws_instance.windows_server[0].private_ip : null
}

output "windows_ad_backup_volume_id" {
  description = "ID del volumen EBS cifrado opcional para el respaldo puntual de estado del sistema AD; null si está deshabilitado."
  value       = var.enable_windows_server && var.enable_ad_system_state_backup ? aws_ebs_volume.windows_ad_backup[0].id : null
}

output "windows_ad_backup_volume_size_gib" {
  description = "Tamaño provisionado del volumen auxiliar para respaldo del estado del sistema AD."
  value       = var.enable_windows_server && var.enable_ad_system_state_backup ? aws_ebs_volume.windows_ad_backup[0].size : null
}

output "windows_egress_proxy_instance_id" {
  description = "ID de la EC2 proxy opcional; null si no se habilitó."
  value       = local.windows_egress_proxy_enabled ? aws_instance.windows_egress_proxy[0].id : null
}

output "windows_egress_proxy_private_ip" {
  description = "IP privada reservada del proxy para mantener las referencias persistentes de Windows al reemplazar la EC2."
  value       = local.windows_egress_proxy_enabled ? aws_instance.windows_egress_proxy[0].private_ip : null
}

output "windows_egress_proxy_enforcement_active" {
  description = "Indica si Terraform retiró el HTTPS directo y fuerza el egress Windows a través del proxy."
  value       = local.windows_egress_proxy_enforcement_active
}

