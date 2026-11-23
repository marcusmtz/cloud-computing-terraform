resource "azurerm_relay_namespace" "norcom_ad" {
  name                = "norcom-ad-relay-demo-2026"
  location            = "Brazil South"
  resource_group_name = azurerm_resource_group.norcom.name
  sku_name            = "Standard"

  tags = {
    project     = "NORCOM"
    environment = "academic-demo"
    purpose     = "private-ad-authentication"
  }
}

resource "azurerm_relay_hybrid_connection" "norcom_ad_auth" {
  name                          = "norcom-ad-auth"
  resource_group_name           = azurerm_resource_group.norcom.name
  relay_namespace_name          = azurerm_relay_namespace.norcom_ad.name
  requires_client_authorization = true
  user_metadata = jsonencode([
    {
      key   = "endpoint"
      value = "norcom-auth.ad.norcom.test:8181"
    }
  ])
}

resource "azurerm_relay_hybrid_connection_authorization_rule" "webapp_send" {
  name                   = "norcom-app-send"
  resource_group_name    = azurerm_resource_group.norcom.name
  namespace_name         = azurerm_relay_namespace.norcom_ad.name
  hybrid_connection_name = azurerm_relay_hybrid_connection.norcom_ad_auth.name
  listen                 = false
  send                   = true
  manage                 = false
}

resource "azurerm_relay_hybrid_connection_authorization_rule" "hcm_listen" {
  name                   = "norcom-hcm-listen"
  resource_group_name    = azurerm_resource_group.norcom.name
  namespace_name         = azurerm_relay_namespace.norcom_ad.name
  hybrid_connection_name = azurerm_relay_hybrid_connection.norcom_ad_auth.name
  listen                 = true
  send                   = false
  manage                 = false
}

resource "azurerm_web_app_hybrid_connection" "intranet_ad_auth" {
  web_app_id    = azurerm_linux_web_app.intranet.id
  relay_id      = azurerm_relay_hybrid_connection.norcom_ad_auth.id
  hostname      = "norcom-auth.ad.norcom.test"
  port          = 8181
  send_key_name = azurerm_relay_hybrid_connection_authorization_rule.webapp_send.name
}

output "ad_relay_namespace" {
  value       = azurerm_relay_namespace.norcom_ad.name
  description = "Azure Relay namespace used by the private NORCOM AD bridge."
}

output "ad_hybrid_connection_name" {
  value       = azurerm_relay_hybrid_connection.norcom_ad_auth.name
  description = "Hybrid Connection endpoint for the private NORCOM auth bridge."
}

output "ad_hcm_listener_connection_string" {
  value       = azurerm_relay_hybrid_connection_authorization_rule.hcm_listen.primary_connection_string
  sensitive   = true
  description = "HCM listener-only Relay connection string; do not print or commit it."
}
