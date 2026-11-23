variable "oci_profile" {
  description = "Nombre del perfil del archivo ~/.oci/config; no guardar llaves en Terraform."
  type        = string
  default     = "DEFAULT"
}

variable "oci_region" {
  description = "Región home para consumir solo la asignación Always Free de la tenancy."
  type        = string
  default     = "sa-vinhedo-1"
}

variable "compartment_ocid" {
  description = "OCID del compartimento para el bucket (usar el compartimento raíz solo si el perfil tiene ese permiso)."
  type        = string
  sensitive   = true
}

variable "object_storage_namespace" {
  description = "Namespace de Object Storage devuelto por OCI; no es una clave de autenticación."
  type        = string
}

variable "bucket_name" {
  description = "Nombre único del bucket privado de respaldos Norcom."
  type        = string
  default     = "norcom-academic-backups-202610"

  validation {
    condition     = length(var.bucket_name) >= 1 && length(var.bucket_name) <= 256
    error_message = "bucket_name debe tener entre 1 y 256 caracteres."
  }
}
