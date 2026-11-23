variable "azure_subscription_id" {
  description = "Optional Azure subscription ID. Leave null to use the active Azure CLI subscription."
  type        = string
  default     = null
}
