variable "aws_region" {
  description = "Región elegida luego de confirmar catálogo y cuotas del Learner Lab."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Prefijo para nombres y etiquetas de recursos."
  type        = string
  default     = "norcom"
}

variable "environment" {
  description = "Entorno académico temporal."
  type        = string
  default     = "u2"
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
  default     = "db.t4g.micro"
}

variable "database_multi_az" {
  description = "Mantiene una réplica standby sincronizada en otra zona para alta disponibilidad. Desactivar solo cuando se solicite reducir costos."
  type        = bool
  default     = true
}

variable "enable_windows_server" {
  description = "Crea de forma opcional un Windows Server c7i-flex.large para administrar Active Directory en el laboratorio."
  type        = bool
  default     = false
}

variable "enable_ad_system_state_backup" {
  description = "Crea de forma opcional un volumen EBS cifrado para un respaldo puntual del estado del sistema AD. No programa respaldos recurrentes."
  type        = bool
  default     = false
}

variable "windows_ad_backup_volume_size" {
  description = "Tamaño del volumen gp3 cifrado para guardar el respaldo puntual del estado del sistema AD."
  type        = number
  default     = 16

  validation {
    condition     = var.windows_ad_backup_volume_size >= 5 && var.windows_ad_backup_volume_size <= 64
    error_message = "windows_ad_backup_volume_size debe estar entre 5 y 64 GiB."
  }
}

variable "enable_windows_egress_proxy" {
  description = "Crea de forma opcional un proxy Squid pequeño para el egreso HTTPS limitado del Windows Server."
  type        = bool
  default     = false
}

variable "enforce_windows_egress_proxy" {
  description = "Retira el egreso HTTPS directo de Windows y lo fuerza a usar el proxy. Activar solo después de configurar y comprobar los clientes del servidor."
  type        = bool
  default     = false
}

variable "windows_proxy_clients_configured" {
  description = "Confirmación explícita de que SSM Agent, CloudWatch Agent, Hybrid Connection Manager y WinHTTP ya apuntan al proxy y pasaron pruebas antes de aplicar el cierre de egreso directo."
  type        = bool
  default     = false
}

variable "windows_egress_proxy_instance_type" {
  description = "Tipo pequeño para el proxy académico. Confirmar disponibilidad y precio en us-east-2 antes de Apply."
  type        = string
  default     = "t3.micro"
}

variable "windows_egress_proxy_allowed_domains" {
  description = "Dominios externos adicionales para el proxy Windows; se suman a los endpoints AWS de la región y deben revisarse antes de cerrar el egreso directo."
  type        = list(string)
  default = [
    ".servicebus.windows.net",
    ".windowsupdate.microsoft.com",
    ".windowsupdate.com",
    ".update.microsoft.com",
    "download.microsoft.com",
    ".delivery.mp.microsoft.com",
    ".prod.do.dsp.mp.microsoft.com",
    "emdl.ws.microsoft.com",
    "tsfe.trafficshaping.dsp.mp.microsoft.com",
    ".wdcp.microsoft.com",
    ".wdcpalt.microsoft.com",
    ".wd.microsoft.com",
  ]

  validation {
    condition     = alltrue([for domain in var.windows_egress_proxy_allowed_domains : can(regex("^\\.?[A-Za-z0-9.-]+$", domain))])
    error_message = "Cada dominio permitido debe contener únicamente letras, números, puntos y guiones; use punto inicial para subdominios."
  }
}

variable "web_origin" {
  description = "Origen del portal; durante desarrollo local se admite http://localhost:4200."
  type        = string
  default     = "https://norcom-portal-demo.azurewebsites.net"

  validation {
    condition     = can(regex("^https://[^/]+$", var.web_origin)) || can(regex("^http://localhost(:[0-9]{1,5})?$", var.web_origin))
    error_message = "web_origin debe ser un origen HTTPS, o localhost para desarrollo, sin ruta ni barra final."
  }
}

variable "intranet_web_origin" {
  description = "Origen HTTPS exacto de la intranet que comparte la cookie firmada con la API ERP."
  type        = string
  default     = "https://norcom-intranet-demo.azurewebsites.net"

  validation {
    condition     = var.intranet_web_origin == "" || can(regex("^https://[^/]+$", var.intranet_web_origin)) || can(regex("^http://localhost(:[0-9]{1,5})?$", var.intranet_web_origin))
    error_message = "intranet_web_origin debe ser un origen HTTPS sin ruta, localhost para desarrollo, o vacío hasta configurar la autenticación."
  }
}

variable "intranet_session_secret" {
  description = "Clave HMAC compartida con la intranet; se obtiene de su almacén local protegido y nunca se escribe en archivos versionados."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.intranet_session_secret) >= 32
    error_message = "intranet_session_secret debe tener al menos 32 caracteres."
  }
}

variable "alert_email" {
  description = "Correo autorizado para recibir alertas operativas de U2."
  type        = string
  default     = "demo@example.invalid"
}

variable "recovery_test_enabled" {
  description = "Crea temporalmente una instancia restaurada desde un snapshot para validar recuperación."
  type        = bool
  default     = false
}

variable "recovery_snapshot_identifier" {
  description = "Identificador del snapshot automático que se restaura en la prueba temporal."
  type        = string
  default     = ""
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

