locals {
  api_name              = "${var.project_name}-${var.environment}-catalog-api"
  inquiry_name          = "${var.project_name}-${var.environment}-public-inquiries"
  bootstrap_name        = "${var.project_name}-${var.environment}-catalog-bootstrap"
  catalog_secret_name   = "${var.project_name}/${var.environment}/catalog-reader"
  inquiry_secret_name   = "${var.project_name}/${var.environment}/public-inquiry-writer"
  private_subnet_ids    = [module.network.subnet_ids_by_tier.private_a, module.network.subnet_ids_by_tier.private_b]
  bootstrap_asset_paths = ["/var/task/schema_v1.sql", "/var/task/001_public_listing_v1.sql", "/var/task/seed_demo.sql"]
}

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-${var.environment}-lambda-sg"
  description = "Egress from catalog functions is limited to RDS and the Secrets Manager endpoint."
  vpc_id      = module.network.vpc_id

  egress {
    description = "PostgreSQL only."
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr, 4, 2), cidrsubnet(var.vpc_cidr, 4, 3)]
  }

  egress {
    description = "Secrets Manager endpoint only."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr, 4, 2)]
  }

  tags = { Name = "${var.project_name}-${var.environment}-lambda-sg" }
}

resource "aws_security_group" "database" {
  name        = "${var.project_name}-${var.environment}-postgres-sg"
  description = "PostgreSQL accepts connections only from the private Lambda security group."
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "Catalog functions only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress = []
  tags   = { Name = "${var.project_name}-${var.environment}-postgres-sg" }
}

resource "aws_security_group" "secrets_endpoint" {
  name        = "${var.project_name}-${var.environment}-secrets-endpoint-sg"
  description = "HTTPS from private catalog functions to Secrets Manager."
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "HTTPS from catalog functions"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress = []
  tags   = { Name = "${var.project_name}-${var.environment}-secrets-endpoint-sg" }
}

resource "aws_db_subnet_group" "norcom" {
  name        = "${var.project_name}-${var.environment}-db-subnets"
  subnet_ids  = local.private_subnet_ids
  description = "RDS stays in both private availability zones; no public subnets."
  tags        = { Name = "${var.project_name}-${var.environment}-db-subnets" }
}

resource "aws_db_instance" "norcom" {
  identifier                  = "${var.project_name}-${var.environment}-postgres"
  engine                      = "postgres"
  instance_class              = var.database_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 20
  storage_type                = "gp2"
  storage_encrypted           = true
  db_name                     = "norcom"
  username                    = "norcom_master"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.norcom.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  publicly_accessible         = false
  multi_az                    = false
  backup_retention_period     = 1
  copy_tags_to_snapshot       = true
  auto_minor_version_upgrade  = true
  apply_immediately           = true
  deletion_protection         = false
  skip_final_snapshot         = true
  delete_automated_backups    = true
  tags                        = { Name = "${var.project_name}-${var.environment}-postgres" }
}

resource "aws_secretsmanager_secret" "catalog_reader" {
  name                    = local.catalog_secret_name
  description             = "Least-privilege PostgreSQL login for the public catalog Lambda."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "inquiry_writer" {
  name                    = local.inquiry_secret_name
  description             = "Restricted PostgreSQL login for the public inquiry Lambda."
  recovery_window_in_days = 0
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [module.network.subnet_ids_by_tier.private_a]
  security_group_ids  = [aws_security_group.secrets_endpoint.id]

  tags = { Name = "${var.project_name}-${var.environment}-secrets-vpce" }
}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.api_name}"
  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "bootstrap" {
  name              = "/aws/lambda/${local.bootstrap_name}"
  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "inquiries" {
  name              = "/aws/lambda/${local.inquiry_name}"
  retention_in_days = 3
}

resource "aws_lambda_function" "api" {
  function_name                  = local.api_name
  role                           = data.aws_iam_role.lab.arn
  runtime                        = "nodejs22.x"
  handler                        = "lambda.handler"
  filename                       = "${path.module}/../../../api/dist/catalog-api-v2.zip"
  source_code_hash               = filebase64sha256("${path.module}/../../../api/dist/catalog-api-v2.zip")
  memory_size                    = 256
  timeout                        = 10
  architectures                  = ["x86_64"]
  reserved_concurrent_executions = 5

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_SECRET_ARN       = aws_secretsmanager_secret.catalog_reader.arn
      PGHOST              = aws_db_instance.norcom.address
      PGPORT              = tostring(aws_db_instance.norcom.port)
      PGDATABASE          = aws_db_instance.norcom.db_name
      PG_POOL_MAX         = "1"
      NODE_EXTRA_CA_CERTS = "/var/runtime/ca-cert.pem"
    }
  }

  depends_on = [aws_cloudwatch_log_group.api]
}

resource "aws_lambda_function" "bootstrap" {
  function_name                  = local.bootstrap_name
  role                           = data.aws_iam_role.lab.arn
  runtime                        = "nodejs22.x"
  handler                        = "bootstrap-catalog-role.handler"
  filename                       = "${path.module}/../../../api/dist/catalog-bootstrap-v2.zip"
  source_code_hash               = filebase64sha256("${path.module}/../../../api/dist/catalog-bootstrap-v2.zip")
  memory_size                    = 256
  timeout                        = 300
  architectures                  = ["x86_64"]
  reserved_concurrent_executions = 1

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_MASTER_SECRET_ARN      = aws_db_instance.norcom.master_user_secret[0].secret_arn
      DB_CATALOG_SECRET_ARN     = aws_secretsmanager_secret.catalog_reader.arn
      DB_INQUIRY_SECRET_ARN     = aws_secretsmanager_secret.inquiry_writer.arn
      DB_INITIALIZE_DEMO_SCHEMA = "true"
      DB_SCHEMA_FILE            = local.bootstrap_asset_paths[0]
      DB_MIGRATION_FILE         = local.bootstrap_asset_paths[1]
      DB_SEED_FILE              = local.bootstrap_asset_paths[2]
      PGHOST                    = aws_db_instance.norcom.address
      PGPORT                    = tostring(aws_db_instance.norcom.port)
      PGDATABASE                = aws_db_instance.norcom.db_name
      NODE_EXTRA_CA_CERTS       = "/var/runtime/ca-cert.pem"
    }
  }

  depends_on = [aws_cloudwatch_log_group.bootstrap]
}

resource "aws_lambda_function" "inquiries" {
  function_name                  = local.inquiry_name
  role                           = data.aws_iam_role.lab.arn
  runtime                        = "nodejs22.x"
  handler                        = "inquiries-lambda.handler"
  filename                       = "${path.module}/../../../api/dist/public-inquiries-v2.zip"
  source_code_hash               = filebase64sha256("${path.module}/../../../api/dist/public-inquiries-v2.zip")
  memory_size                    = 256
  timeout                        = 10
  architectures                  = ["x86_64"]
  reserved_concurrent_executions = 3

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_INQUIRY_SECRET_ARN = aws_secretsmanager_secret.inquiry_writer.arn
      PGHOST                = aws_db_instance.norcom.address
      PGPORT                = tostring(aws_db_instance.norcom.port)
      PGDATABASE            = aws_db_instance.norcom.db_name
      NODE_EXTRA_CA_CERTS   = "/var/runtime/ca-cert.pem"
    }
  }

  depends_on = [aws_cloudwatch_log_group.inquiries]
}

resource "aws_apigatewayv2_api" "catalog" {
  name          = "${var.project_name}-${var.environment}-catalog"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [var.web_origin]
    allow_methods = ["GET", "POST"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "catalog_lambda" {
  api_id                 = aws_apigatewayv2_api.catalog.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_integration" "inquiries_lambda" {
  api_id                 = aws_apigatewayv2_api.catalog.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.inquiries.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "GET /healthz"
  target    = "integrations/${aws_apigatewayv2_integration.catalog_lambda.id}"
}

resource "aws_apigatewayv2_route" "listings" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "GET /api/v1/listings"
  target    = "integrations/${aws_apigatewayv2_integration.catalog_lambda.id}"
}

resource "aws_apigatewayv2_route" "listing_detail" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "GET /api/v1/listings/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.catalog_lambda.id}"
}

resource "aws_apigatewayv2_route" "public_inquiries" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "POST /api/v1/public/inquiries"
  target    = "integrations/${aws_apigatewayv2_integration.inquiries_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.catalog.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.catalog.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_inquiries" {
  statement_id  = "AllowHttpApiInvokePublicInquiries"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inquiries.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.catalog.execution_arn}/*/*"
}
