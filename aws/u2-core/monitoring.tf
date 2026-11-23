resource "aws_sns_topic" "ops_alerts" {
  name = "${var.project_name}-${var.environment}-ops-alerts"
}

resource "aws_sns_topic_subscription" "ops_email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "catalog_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-catalog-errors"
  alarm_description   = "La función del catálogo devolvió al menos un error en cinco minutos."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.api.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "inquiry_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-inquiry-errors"
  alarm_description   = "La función de consultas devolvió al menos un error en cinco minutos."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.inquiries.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu"
  alarm_description   = "CPU de PostgreSQL superior al 80 por ciento durante diez minutos."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.norcom.identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-free-storage"
  alarm_description   = "Quedan menos de 5 GiB libres en PostgreSQL."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.norcom.identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5368709120
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-api-5xx"
  alarm_description   = "API Gateway registró errores HTTP 5xx."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.catalog.id, Stage = aws_apigatewayv2_stage.default.name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_lambda_throttles" {
  alarm_name          = "${var.project_name}-${var.environment}-catalog-throttles"
  alarm_description   = "La función de catálogo llegó a su concurrencia reservada."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = aws_lambda_function.api.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-connections"
  alarm_description   = "Las conexiones PostgreSQL superaron el umbral operativo del laboratorio."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.norcom.identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 30
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name        = "${var.project_name}-${var.environment}-api-latency-p95"
  alarm_description = "El percentil 95 de latencia de API Gateway superó tres segundos."
  namespace         = "AWS/ApiGateway"
  metric_name       = "Latency"
  dimensions = {
    ApiId = aws_apigatewayv2_api.catalog.id
    Stage = aws_apigatewayv2_stage.default.name
  }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "windows_instance_status" {
  count = var.enable_windows_server ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-windows-instance-status"
  alarm_description   = "Falló la comprobación de estado de la EC2 que aloja Active Directory."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.windows_server[0].id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "windows_cpu" {
  count = var.enable_windows_server ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-windows-cpu"
  alarm_description   = "La CPU de la EC2 que aloja Active Directory superó 85 por ciento durante diez minutos."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.windows_server[0].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
}

resource "aws_cloudwatch_dashboard" "norcom_operations" {
  dashboard_name = "${var.project_name}-${var.environment}-operations"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title = "API Gateway: errores y latencia p95"
          view  = "timeSeries", region = var.aws_region, period = 300
          metrics = [
            ["AWS/ApiGateway", "5xx", "ApiId", aws_apigatewayv2_api.catalog.id, "Stage", aws_apigatewayv2_stage.default.name, { label = "5xx" }],
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.catalog.id, "Stage", aws_apigatewayv2_stage.default.name, { stat = "p95", yAxis = "right", label = "p95 ms" }]
          ]
          yAxis = { left = { min = 0 }, right = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title = "Lambda: errores, throttles y duración"
          view  = "timeSeries", region = var.aws_region, period = 300
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.api.function_name, { label = "Catálogo errores" }],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.api.function_name, { label = "Catálogo throttles" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "p95", yAxis = "right", label = "Catálogo p95 ms" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.inquiries.function_name, { label = "Consultas errores" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title = "RDS PostgreSQL: CPU, conexiones y almacenamiento libre"
          view  = "timeSeries", region = var.aws_region, period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.norcom.identifier, { label = "CPU %" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.norcom.identifier, { yAxis = "right", label = "Conexiones" }],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.norcom.identifier, { yAxis = "right", label = "Almacenamiento libre bytes" }]
          ]
        }
      },
      {
        type = "alarm", x = 12, y = 6, width = 12, height = 6,
        properties = { title = "Estado de alarmas de NORCOM U2", alarms = concat([
          aws_cloudwatch_metric_alarm.catalog_errors.arn,
          aws_cloudwatch_metric_alarm.inquiry_errors.arn,
          aws_cloudwatch_metric_alarm.rds_cpu.arn,
          aws_cloudwatch_metric_alarm.rds_storage.arn,
          aws_cloudwatch_metric_alarm.api_5xx.arn,
          aws_cloudwatch_metric_alarm.api_lambda_throttles.arn,
          aws_cloudwatch_metric_alarm.rds_connections.arn,
          aws_cloudwatch_metric_alarm.api_latency.arn
          ], var.enable_windows_server ? [
          aws_cloudwatch_metric_alarm.windows_instance_status[0].arn,
          aws_cloudwatch_metric_alarm.windows_cpu[0].arn
        ] : []) }
      }
    ]
  })
}
