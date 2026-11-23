resource "aws_cloudwatch_metric_alarm" "mail_instance_status" {
  alarm_name          = "norcom-u2-mail-instance-status"
  alarm_description   = "La comprobación de estado de la instancia de webmail falló."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.mail.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "mail_cpu" {
  alarm_name          = "norcom-u2-mail-cpu"
  alarm_description   = "El uso de CPU del servidor Roundcube/Postfix/Dovecot superó 80 por ciento."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.mail.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
}

resource "aws_cloudwatch_dashboard" "mail_operations" {
  dashboard_name = "norcom-u2-mail-operations"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title = "Roundcube EC2: CPU y comprobaciones de estado"
          view  = "timeSeries", region = var.aws_region, period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.mail.id, { label = "CPU %" }],
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.mail.id, { yAxis = "right", label = "Fallo de estado" }]
          ]
        }
      },
      {
        type = "alarm", x = 12, y = 0, width = 12, height = 6,
        properties = { title = "Alarmas del webmail", alarms = [
          aws_cloudwatch_metric_alarm.mail_instance_status.arn,
          aws_cloudwatch_metric_alarm.mail_cpu.arn
        ] }
      }
    ]
  })
}
