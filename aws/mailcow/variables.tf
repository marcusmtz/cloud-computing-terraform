variable "aws_region" {
  description = "Región donde se despliega la demostración de correo."
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC de NORCOM U2 existente en us-east-2."
  type        = string
}

variable "public_subnet_id" {
  description = "Subred pública de la VPC de NORCOM U2."
  type        = string
}

variable "ssh_public_key" {
  description = "Clave pública de administración; la privada no entra en Terraform."
  type        = string
}

variable "enable_public_mail" {
  description = "Obsoleto y conservado por compatibilidad; no habilita puertos ni cambia reglas de red."
  type        = bool
  default     = false
}

variable "enable_public_smtp_receive" {
  description = "Abre SMTP entrante público solo si el proyecto incorpora recepción desde otros servidores."
  type        = bool
  default     = false
}

variable "enable_mail_clients" {
  description = "Expose IMAPS and authenticated SMTP submission for external clients."
  type        = bool
  default     = false
}

variable "mail_domain" {
  description = "Subdomain for internal demonstration mailboxes."
  type        = string
  default     = "lab.example.invalid"
}

variable "contact_email" {
  description = "Contact address for Let's Encrypt certificate registration."
  type        = string
  default     = "demo@example.invalid"
}

variable "alarm_topic_arn" {
  description = "Tema SNS existente para alertas del servidor de correo."
  type        = string
}
