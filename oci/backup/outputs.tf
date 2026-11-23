output "bucket_name" {
  description = "Nombre del bucket privado para scripts de respaldo."
  value       = oci_objectstorage_bucket.norcom_backup.name
}

output "bucket_namespace" {
  description = "Namespace de Object Storage asociado al bucket."
  value       = oci_objectstorage_bucket.norcom_backup.namespace
}

output "bucket_id" {
  description = "OCID del bucket; tratarlo como dato de infraestructura y no publicarlo en capturas."
  value       = oci_objectstorage_bucket.norcom_backup.id
  sensitive   = true
}
