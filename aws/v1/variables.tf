variable "aws_region" {
  description = "Región elegida luego de confirmar catálogo y cuotas del Learner Lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombres y etiquetas de recursos."
  type        = string
  default     = "norcom"
}

variable "environment" {
  description = "Entorno académico temporal."
  type        = string
  default     = "lab"
}

variable "vpc_cidr" {
  description = "Bloque privado reservado para la VPC de Norcom."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un bloque IPv4 CIDR válido."
  }
}

variable "database_instance_class" {
  description = "Clase que debe figurar permitida en el catálogo del Learner Lab y caber en el crédito."
  type        = string
  default     = "db.t3.micro"
}

variable "web_origin" {
  description = "Origen del portal; durante desarrollo local se admite http://localhost:4200."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+$", var.web_origin)) || can(regex("^http://localhost(:[0-9]{1,5})?$", var.web_origin))
    error_message = "web_origin debe ser un origen HTTPS, o localhost para desarrollo, sin ruta ni barra final."
  }
}

variable "ad_domain_name" {
  description = "Dominio DNS privado para usuarios y servicios internos de Norcom."
  type        = string
  default     = "ad.norcom.test"

  validation {
    condition     = can(regex("^([a-z0-9]+(-[a-z0-9]+)*\\.)+[a-z]{2,}$", var.ad_domain_name))
    error_message = "ad_domain_name debe ser un nombre DNS interno válido, por ejemplo ad.norcom.test."
  }
}

variable "ad_admin_password" {
  description = "Contraseña inicial sensible del administrador delegado de Managed AD. No almacenarla en tfvars, repositorio ni salidas compartidas."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.ad_admin_password) >= 12 && can(regex("[A-Z]", var.ad_admin_password)) && can(regex("[a-z]", var.ad_admin_password)) && can(regex("[0-9]", var.ad_admin_password)) && can(regex("[^A-Za-z0-9]", var.ad_admin_password))
    error_message = "La contraseña debe tener al menos 12 caracteres e incluir mayúscula, minúscula, número y símbolo."
  }
}
