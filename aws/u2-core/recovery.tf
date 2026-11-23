resource "aws_db_snapshot" "recovery_validation" {
  count                  = var.recovery_test_enabled ? 1 : 0
  db_instance_identifier = aws_db_instance.norcom.identifier
  db_snapshot_identifier = var.recovery_snapshot_identifier

  tags = {
    Name    = "${var.project_name}-${var.environment}-restore-check"
    Purpose = "temporary-recovery-validation"
  }
}

resource "aws_db_instance" "recovery_validation" {
  count = var.recovery_test_enabled ? 1 : 0

  identifier                  = "${var.project_name}-${var.environment}-restore-check"
  snapshot_identifier         = aws_db_snapshot.recovery_validation[0].id
  instance_class              = var.database_instance_class
  db_subnet_group_name        = aws_db_subnet_group.norcom.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  publicly_accessible         = false
  multi_az                    = false
  storage_encrypted           = true
  backup_retention_period     = 0
  manage_master_user_password = true
  apply_immediately           = true
  skip_final_snapshot         = true
  delete_automated_backups    = true
  deletion_protection         = false

  tags = {
    Name    = "${var.project_name}-${var.environment}-restore-check"
    Purpose = "temporary-recovery-validation"
  }

  lifecycle {
    precondition {
      condition     = trimspace(var.recovery_snapshot_identifier) != ""
      error_message = "recovery_snapshot_identifier debe apuntar a un snapshot disponible."
    }
  }
}

resource "aws_cloudwatch_log_group" "recovery_validation" {
  count             = var.recovery_test_enabled ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-${var.environment}-restore-check"
  retention_in_days = 3
}

resource "aws_lambda_function" "recovery_validation" {
  count                          = var.recovery_test_enabled ? 1 : 0
  function_name                  = "${var.project_name}-${var.environment}-restore-check"
  role                           = aws_iam_role.recovery_validation[0].arn
  runtime                        = "nodejs22.x"
  handler                        = "recovery-validation.handler"
  filename                       = "${path.module}/../../../api/dist/recovery-validation.zip"
  source_code_hash               = filebase64sha256("${path.module}/../../../api/dist/recovery-validation.zip")
  memory_size                    = 256
  timeout                        = 15
  reserved_concurrent_executions = 1

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_SECRET_ARN       = aws_db_instance.recovery_validation[0].master_user_secret[0].secret_arn
      PGHOST              = aws_db_instance.recovery_validation[0].address
      PGPORT              = tostring(aws_db_instance.recovery_validation[0].port)
      PGDATABASE          = aws_db_instance.recovery_validation[0].db_name
      PG_POOL_MAX         = "1"
      NODE_EXTRA_CA_CERTS = "/var/runtime/ca-cert.pem"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.recovery_validation,
    aws_iam_role_policy.recovery_validation_secret,
    aws_iam_role_policy.vpc_logs,
  ]
}
