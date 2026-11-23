resource "oci_objectstorage_bucket" "norcom_backup" {
  compartment_id = var.compartment_ocid
  name           = var.bucket_name
  namespace      = var.object_storage_namespace

  access_type  = "NoPublicAccess"
  storage_tier = "Standard"
  versioning   = "Disabled"

  freeform_tags = {
    Project     = "norcom-cloud-academic"
    Environment = "lab"
    Purpose     = "encrypted-cross-cloud-backup"
  }
}
