terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi   = { source = "Azure/azapi", version = "~> 2.13" }
  }
}

provider "azurerm" {
  subscription_id                 = var.azure_subscription_id
  resource_provider_registrations = "none"
  features {}
}

provider "azapi" {}

resource "azurerm_resource_group" "norcom" {
  name     = "norcom"
  location = "Brazil South"
  lifecycle { ignore_changes = all }
}

resource "azurerm_service_plan" "norcom" {
  name                = "ASP-norcom-8f61"
  resource_group_name = azurerm_resource_group.norcom.name
  # Keep the live region fixed. The imported resource-group state had stale location data.
  location     = "Brazil South"
  os_type      = "Linux"
  sku_name     = var.app_service_sku
  worker_count = var.app_service_instances
}

resource "azurerm_linux_web_app" "portal" {
  name                = "norcom-portal-demo"
  resource_group_name = azurerm_resource_group.norcom.name
  location            = azurerm_resource_group.norcom.location
  service_plan_id     = azurerm_service_plan.norcom.id
  https_only          = true
  site_config {
    app_command_line = "node server.mjs"
    application_stack { node_version = "22-lts" }
  }
  # Existing app settings and package deployment are reconciled idempotently by
  # scripts/deploy-multicloud.ps1; avoid replacing the live App Service settings.
  lifecycle { ignore_changes = all }
}

# The public portal uses a subdomain managed in Cloudflare. The CNAME must be
# DNS-only while Azure validates/renews its free managed certificate; the
# asuid TXT record proves ownership. DNS stays external to this Terraform state.
resource "azurerm_app_service_custom_hostname_binding" "portal" {
  hostname            = var.portal_custom_hostname
  app_service_name    = azurerm_linux_web_app.portal.name
  resource_group_name = azurerm_resource_group.norcom.name

  # Certificate binding below owns these two fields.
  lifecycle {
    ignore_changes = [ssl_state, thumbprint]
  }
}

resource "azurerm_app_service_managed_certificate" "portal" {
  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.portal.id

  # Imported Azure-managed certificates do not expose this association in
  # Terraform state on refresh. Keep the existing managed certificate stable.
  lifecycle {
    ignore_changes = [custom_hostname_binding_id]
  }
}

resource "azurerm_app_service_certificate_binding" "portal" {
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.portal.id
  certificate_id      = azurerm_app_service_managed_certificate.portal.id
  ssl_state           = "SniEnabled"
}

resource "azurerm_linux_web_app" "intranet" {
  name                = "norcomDeparments"
  resource_group_name = azurerm_resource_group.norcom.name
  location            = azurerm_resource_group.norcom.location
  service_plan_id     = azurerm_service_plan.norcom.id
  https_only          = true
  site_config {
    app_command_line = "node server.mjs"
    application_stack { node_version = "22-lts" }
  }
  # The orchestrator updates selected runtime settings without replacing the
  # existing appsettings collection, which also contains dynamic auth values.
  lifecycle { ignore_changes = all }
}

# Keep health-check configuration in Terraform without refreshing/replacing the
# imported web apps, whose live resource-group location differs from old state.
# Both Node servers already return HTTP 200 on /healthz.
resource "azapi_update_resource" "portal_health_check" {
  type        = "Microsoft.Web/sites/config@2022-03-01"
  resource_id = "${azurerm_linux_web_app.portal.id}/config/web"
  body = {
    properties = {
      healthCheckPath = "/healthz"
    }
  }
}

resource "azapi_update_resource" "intranet_health_check" {
  type        = "Microsoft.Web/sites/config@2022-03-01"
  resource_id = "${azurerm_linux_web_app.intranet.id}/config/web"
  body = {
    properties = {
      healthCheckPath = "/healthz"
    }
  }
}

output "portal_url" { value = "https://${azurerm_linux_web_app.portal.default_hostname}" }
output "intranet_url" { value = "https://${azurerm_linux_web_app.intranet.default_hostname}" }
output "portal_custom_url" { value = "https://${var.portal_custom_hostname}" }
