locals {
  ad_package_storage_name = "norcomadpkgdemo26"
  ad_package_container    = "packages"
}

# Private, low-cost artifact store used by App Service Run From Package.
# App Service reads the ZIP with its user-assigned identity; no SAS is stored.
resource "azapi_resource" "intranet_package_storage" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  parent_id = azurerm_resource_group.norcom.id
  name      = local.ad_package_storage_name
  # Keep this resource beside the existing App Service. The resource group's
  # metadata location is Central US, while the live web app is in Brazil South.
  location = "Brazil South"
  tags = {
    project     = "NORCOM"
    environment = "academic-demo"
    purpose     = "private-intranet-deployment-package"
  }

  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      accessTier                  = "Hot"
      allowBlobPublicAccess       = false
      allowCrossTenantReplication = false
      minimumTlsVersion           = "TLS1_2"
      publicNetworkAccess         = "Enabled"
      supportsHttpsTrafficOnly    = true
    }
  }

  response_export_values = []
}

resource "azapi_resource" "intranet_package_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01"
  parent_id = "${azapi_resource.intranet_package_storage.id}/blobServices/default"
  name      = local.ad_package_container

  body = {
    properties = {
      publicAccess = "None"
    }
  }

  response_export_values = []
}

resource "azurerm_user_assigned_identity" "intranet_package_reader" {
  name                = "norcom-intranet-package-reader"
  location            = "Brazil South"
  resource_group_name = azurerm_resource_group.norcom.name
  tags = {
    project     = "NORCOM"
    environment = "academic-demo"
    purpose     = "private-intranet-deployment-package"
  }
}

resource "azurerm_role_assignment" "intranet_package_reader" {
  scope                            = azapi_resource.intranet_package_container.id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = azurerm_user_assigned_identity.intranet_package_reader.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# The web app resource is imported and intentionally protected from broad
# Terraform updates. Attach the package-only identity with a narrow ARM patch.
resource "azapi_update_resource" "intranet_package_identity" {
  type        = "Microsoft.Web/sites@2022-03-01"
  resource_id = azurerm_linux_web_app.intranet.id

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.intranet_package_reader.id) = {}
      }
    }
  }

  response_export_values = []
}

output "intranet_package_storage_name" {
  value       = local.ad_package_storage_name
  description = "Private Azure Storage account that holds the current intranet deployment ZIP."
}

output "intranet_package_container_name" {
  value       = local.ad_package_container
  description = "Private container for versioned intranet packages."
}

output "intranet_package_identity_id" {
  value       = azurerm_user_assigned_identity.intranet_package_reader.id
  description = "User-assigned identity used by App Service to read the private ZIP."
}

output "intranet_package_identity_client_id" {
  value       = azurerm_user_assigned_identity.intranet_package_reader.client_id
  description = "Client ID used to identify the package-reader identity in App Service settings."
}
