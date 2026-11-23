variable "oci_profile" {
  type    = string
  default = "DEFAULT"
}

variable "compartment_ocid" {
  description = "Compartimento raíz o dedicado donde se ubicará el laboratorio."
  type        = string
}

variable "availability_domain" {
  description = "Dominio de disponibilidad de Vinhedo con cuota A1 libre."
  type        = string
}

variable "fault_domain" {
  description = "Zona física de Vinhedo; permite intentar otra capacidad Always Free."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Clave pública exclusiva para administrar la VM."
  type        = string
}

variable "admin_cidr" {
  description = "IPv4 /32 desde la que se permite SSH y HTTPS durante la preparación."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr debe ser una IPv4 /32."
  }
}

variable "ocpus" {
  description = "OCPU A1; una unidad permite probar la disponibilidad gratuita con un consumo mínimo."
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "RAM de la VM; Mailcow requiere al menos 6 GiB más swap."
  type        = number
  default     = 8

  validation {
    condition     = var.memory_in_gbs >= 8
    error_message = "La demostración de Mailcow necesita al menos 8 GiB de RAM."
  }
}

variable "enable_public_mail" {
  description = "Abrir SMTP entrante y HTTPS público solo después de configurar Mailcow, TLS y DNS."
  type        = bool
  default     = false
}

variable "enable_mail_clients" {
  description = "Abrir IMAPS y submission al público cuando se prueben clientes externos."
  type        = bool
  default     = false
}
