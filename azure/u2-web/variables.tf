variable "app_service_sku" {
  description = "Tier del plan que aloja el portal y la intranet. B1 habilita réplicas dedicadas; F1 es el modo económico de una sola instancia."
  type        = string
  default     = "B1"

  validation {
    condition     = contains(["F1", "B1"], var.app_service_sku)
    error_message = "app_service_sku debe ser B1 para redundancia o F1 para el modo de costo mínimo."
  }
}

variable "app_service_instances" {
  description = "Número de instancias compartidas por el portal y la intranet."
  type        = number
  default     = 2

  validation {
    condition     = var.app_service_sku == "F1" ? var.app_service_instances == 1 : var.app_service_instances >= 1 && var.app_service_instances <= 3
    error_message = "F1 admite una sola instancia; B1 admite de una a tres instancias."
  }
}

variable "portal_custom_hostname" {
  description = "Hostname público del portal; debe tener un CNAME directo al App Service y el TXT asuid correspondiente en Cloudflare."
  type        = string
  default     = "portal.example.invalid"
}
