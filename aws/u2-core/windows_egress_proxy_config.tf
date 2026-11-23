resource "aws_ssm_document" "windows_egress_proxy_config" {
  count           = local.windows_egress_proxy_enabled ? 1 : 0
  name            = "${var.project_name}-${var.environment}-windows-egress-proxy-config"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Actualiza la lista permitida de Squid de NORCOM sin sustituir la instancia proxy."
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "ApplySquidConfiguration"
      inputs = {
        timeoutSeconds = "300"
        runCommand = [templatefile("${path.module}/templates/configure-squid-proxy.sh.tftpl", {
          allowed_domains = join(" ", local.windows_egress_proxy_allowed_domains)
        })]
      }
    }]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-windows-egress-proxy-config"
    Component = "windows-egress-proxy"
  }
}

resource "aws_ssm_association" "windows_egress_proxy_config" {
  count = local.windows_egress_proxy_enabled ? 1 : 0

  name             = aws_ssm_document.windows_egress_proxy_config[0].name
  document_version = aws_ssm_document.windows_egress_proxy_config[0].latest_version
  association_name = "${var.project_name}-${var.environment}-windows-egress-proxy-config"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_egress_proxy[0].id]
  }

  wait_for_success_timeout_seconds = 600

  depends_on = [aws_iam_role_policy_attachment.windows_egress_proxy_ssm]
}
