output "vpc_id" {
  description = "ID de la VPC Norcom."
  value       = aws_vpc.norcom.id
}

output "vpc_cidr" {
  description = "Bloque CIDR de la VPC."
  value       = aws_vpc.norcom.cidr_block
}

output "availability_zones" {
  description = "Las dos zonas seleccionadas por el proveedor para esta cuenta/región."
  value       = local.selected_azs
}

output "subnet_ids_by_tier" {
  description = "IDs de subredes separadas por nivel; las privadas no tienen ruta de salida a Internet."
  value = {
    for name, subnet in aws_subnet.tier : name => subnet.id
  }
}

output "private_route_table_id" {
  description = "Tabla compartida por las dos subredes privadas para endpoints gateway sin NAT."
  value       = aws_route_table.private.id
}

