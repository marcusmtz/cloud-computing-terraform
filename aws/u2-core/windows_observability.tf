locals {
  windows_event_channels = [
    "System",
    "Application",
    "Directory Service",
    "DNS Server",
  ]
}

resource "aws_cloudwatch_log_group" "windows_services" {
  count = var.enable_windows_server ? 1 : 0

  name              = "/aws/ec2/${var.project_name}-${var.environment}/windows-services"
  retention_in_days = 7
}

resource "aws_ssm_parameter" "windows_cloudwatch_agent" {
  count = var.enable_windows_server ? 1 : 0

  name        = "AmazonCloudWatch-${var.project_name}-${var.environment}-windows"
  description = "Canales de sistema, aplicación, AD DS y DNS; solo advertencias y errores."
  type        = "String"
  value = jsonencode({
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            for channel in local.windows_event_channels : {
              event_name      = channel
              event_levels    = ["CRITICAL", "ERROR", "WARNING"]
              event_format    = "text"
              log_group_name  = aws_cloudwatch_log_group.windows_services[0].name
              log_stream_name = "{instance_id}-${replace(lower(channel), " ", "-")}"
            }
          ]
        }
      }
    }
  })
}

resource "aws_iam_role_policy" "windows_cloudwatch_logs" {
  count = var.enable_windows_server ? 1 : 0

  name = "${var.project_name}-${var.environment}-windows-cloudwatch-logs"
  role = aws_iam_role.windows_server[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAgentConfiguration"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [aws_ssm_parameter.windows_cloudwatch_agent[0].arn]
      },
      {
        Sid    = "WriteWindowsServiceLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
        ]
        Resource = ["${aws_cloudwatch_log_group.windows_services[0].arn}:*"]
      },
    ]
  })
}

resource "aws_ssm_association" "windows_cloudwatch_agent_install" {
  count = var.enable_windows_server ? 1 : 0

  name             = "AWS-ConfigureAWSPackage"
  association_name = "${var.project_name}-${var.environment}-windows-cwagent-install"
  parameters = {
    action  = "Install"
    name    = "AmazonCloudWatchAgent"
    version = "latest"
  }
  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_server[0].id]
  }
  wait_for_success_timeout_seconds = 1800
}

resource "aws_ssm_association" "windows_cloudwatch_agent_configure" {
  count = var.enable_windows_server ? 1 : 0

  name             = "AmazonCloudWatch-ManageAgent"
  association_name = "${var.project_name}-${var.environment}-windows-cwagent-configure"
  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.windows_cloudwatch_agent[0].name
    optionalRestart               = "yes"
  }
  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_server[0].id]
  }
  wait_for_success_timeout_seconds = 1800

  depends_on = [
    aws_iam_role_policy.windows_cloudwatch_logs,
    aws_ssm_association.windows_cloudwatch_agent_install,
  ]
}
