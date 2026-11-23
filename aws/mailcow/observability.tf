resource "aws_cloudwatch_log_group" "mail_services" {
  name              = "/aws/ec2/norcom-u2/mail-services"
  retention_in_days = 7
}

resource "aws_ssm_parameter" "mail_cloudwatch_agent" {
  name        = "AmazonCloudWatch-norcom-u2-mail"
  description = "Solo advertencias y errores de los registros locales de Postfix y Dovecot."
  type        = "String"
  value = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/mail.log"
              log_group_name  = aws_cloudwatch_log_group.mail_services.name
              log_stream_name = "{instance_id}-mail"
              filters = [{
                type       = "include"
                expression = "(?i)(warning|error|fatal|panic|reject|failed)"
              }]
            },
            {
              file_path       = "/var/log/mail.err"
              log_group_name  = aws_cloudwatch_log_group.mail_services.name
              log_stream_name = "{instance_id}-mail-errors"
            },
          ]
        }
      }
    }
  })
}

resource "aws_iam_role_policy" "mail_cloudwatch_logs" {
  name = "norcom-u2-mail-cloudwatch-logs"
  role = aws_iam_role.mail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAgentConfiguration"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [aws_ssm_parameter.mail_cloudwatch_agent.arn]
      },
      {
        Sid    = "WriteMailServiceLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
        ]
        Resource = ["${aws_cloudwatch_log_group.mail_services.arn}:*"]
      },
    ]
  })
}

resource "aws_ssm_association" "mail_cloudwatch_agent_install" {
  name             = "AWS-ConfigureAWSPackage"
  association_name = "norcom-u2-mail-cwagent-install"
  parameters = {
    action  = "Install"
    name    = "AmazonCloudWatchAgent"
    version = "latest"
  }
  targets {
    key    = "InstanceIds"
    values = [aws_instance.mail.id]
  }
  wait_for_success_timeout_seconds = 1800
}

resource "aws_ssm_association" "mail_cloudwatch_agent_configure" {
  name             = "AmazonCloudWatch-ManageAgent"
  association_name = "norcom-u2-mail-cwagent-configure"
  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.mail_cloudwatch_agent.name
    optionalRestart               = "yes"
  }
  targets {
    key    = "InstanceIds"
    values = [aws_instance.mail.id]
  }
  wait_for_success_timeout_seconds = 1800

  depends_on = [
    aws_iam_role_policy.mail_cloudwatch_logs,
    aws_ssm_association.mail_cloudwatch_agent_install,
  ]
}
