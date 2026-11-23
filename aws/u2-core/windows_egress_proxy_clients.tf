resource "aws_ssm_document" "windows_egress_proxy_clients" {
  count           = var.enable_windows_server ? 1 : 0
  name            = "${var.project_name}-${var.environment}-windows-egress-proxy-clients"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configura o restaura el proxy de egreso para los clientes de Windows de NORCOM."
    parameters = {
      Mode = {
        type        = "String"
        description = "Configure para usar Squid o Restore para devolver la configuración previa."
      }
      ProxyUrl = {
        type        = "String"
        description = "URL HTTP del proxy privado."
      }
      ProxyHost = {
        type        = "String"
        description = "IP privada actual del proxy."
      }
      AwsRegion = {
        type        = "String"
        description = "Región AWS usada por el agente SSM."
      }
    }
    mainSteps = [{
      action = "aws:runPowerShellScript"
      name   = "ConfigureOrRestoreProxyClients"
      inputs = {
        timeoutSeconds = "900"
        runCommand = [templatefile("${path.module}/templates/configure-windows-proxy-clients.ps1.tftpl", {
          mode       = "{{ Mode }}"
          proxy_url  = "{{ ProxyUrl }}"
          proxy_host = "{{ ProxyHost }}"
          aws_region = "{{ AwsRegion }}"
        })]
      }
    }]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-windows-egress-proxy-clients"
    Component = "windows-egress-proxy"
  }
}

resource "aws_ssm_association" "windows_egress_proxy_clients" {
  count = var.enable_windows_server ? 1 : 0

  name             = aws_ssm_document.windows_egress_proxy_clients[0].name
  association_name = "${var.project_name}-${var.environment}-windows-egress-proxy-clients"
  parameters = {
    Mode      = local.windows_egress_proxy_enabled ? "Configure" : "Restore"
    ProxyUrl  = local.windows_egress_proxy_enabled ? "http://${aws_instance.windows_egress_proxy[0].private_ip}:3128" : ""
    ProxyHost = local.windows_egress_proxy_enabled ? aws_instance.windows_egress_proxy[0].private_ip : ""
    AwsRegion = var.aws_region
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_server[0].id]
  }

  wait_for_success_timeout_seconds = 900

  depends_on = [
    aws_instance.windows_egress_proxy,
    aws_ssm_association.windows_cloudwatch_agent_configure,
  ]
}
