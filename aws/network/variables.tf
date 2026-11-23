variable "aws_region" {
  description = "Región del laboratorio AWS validada antes de la ejecución."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre corto empleado en etiquetas y nombres de recursos."
  type        = string
  default     = "norcom"
}

variable "environment" {
  description = "Entorno lógico de laboratorio."
  type        = string
  default     = "lab"
}

variable "vpc_cidr" {
  description = "Bloque privado reservado para la VPC inicial de Norcom."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un bloque IPv4 CIDR válido."
  }
}

