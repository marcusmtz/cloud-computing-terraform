locals {
  api_name                     = "${var.project_name}-${var.environment}-catalog-api"
  erp_name                     = "${var.project_name}-${var.environment}-erp-api"
  inquiry_name                 = "${var.project_name}-${var.environment}-public-inquiries"
  bootstrap_name               = "${var.project_name}-${var.environment}-catalog-bootstrap"
  catalog_secret_name          = "${var.project_name}/${var.environment}/catalog-reader"
  erp_secret_name              = "${var.project_name}/${var.environment}/erp-runtime"
  erp_session_name             = "${var.project_name}/${var.environment}/intranet-session-signing"
  inquiry_secret_name          = "${var.project_name}/${var.environment}/public-inquiry-writer"
  private_subnet_ids           = [module.network.subnet_ids_by_tier.private_a, module.network.subnet_ids_by_tier.private_b]
  bootstrap_asset_paths        = ["/var/task/schema_v1.sql", "/var/task/001_public_listing_v1.sql", "/var/task/seed_demo.sql"]
  erp_migration_path           = "/var/task/002_property_visits.sql"
  erp_financial_migration_path = "/var/task/003_contract_finance.sql"
  erp_document_migration_path  = "/var/task/004_erp_documents.sql"
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
    description = "Secrets Manager interface endpoints in both private availability zones."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr, 4, 2), cidrsubnet(var.vpc_cidr, 4, 3)]
  }

  egress {
    description     = "HTTPS to the private S3 gateway endpoint for document metadata verification."
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
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
  identifier        = "${var.project_name}-${var.environment}-postgres"
  engine            = "postgres"
  instance_class    = var.database_instance_class
  allocated_storage = 20
  # Keep autoscaling enabled with the smallest whole-GiB cap above AWS's
  # recommended 26% headroom (20 GiB * 1.26 = 25.2 GiB).
  max_allocated_storage       = 26
  storage_type                = "gp2"
  storage_encrypted           = true
  db_name                     = "norcom"
  username                    = "norcom_master"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.norcom.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  publicly_accessible         = false
  multi_az                    = var.database_multi_az
  # The current AWS Free Tier account rejects retention above one day.
  # Keep the supported minimum here; longer recovery retention needs an account-plan change.
  backup_retention_period    = 1
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = false
  skip_final_snapshot        = true
  delete_automated_backups   = true

  lifecycle {
    precondition {
      condition = !var.enforce_windows_egress_proxy || (
        var.enable_windows_server &&
        var.enable_windows_egress_proxy &&
        var.windows_proxy_clients_configured
      )
      error_message = "No se puede cerrar el egreso HTTPS directo: primero habilite Windows y el proxy, configure SSM/CloudWatch/HCM/WinHTTP y confirme las pruebas con windows_proxy_clients_configured=true."
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-postgres" }
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

resource "aws_secretsmanager_secret" "erp_runtime" {
  name                    = local.erp_secret_name
  description             = "Least-privilege PostgreSQL login for the authenticated internal ERP API."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "erp_session_signing" {
  name                    = local.erp_session_name
  description             = "Shared HMAC signing key used by the Azure intranet session and AWS ERP API."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "erp_session_signing" {
  secret_id     = aws_secretsmanager_secret.erp_session_signing.id
  secret_string = var.intranet_session_secret
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.secrets_endpoint.id]

  tags = { Name = "${var.project_name}-${var.environment}-secrets-vpce" }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "s3_gateway_endpoint" {
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.erp_documents.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.network.private_route_table_id]
  policy            = data.aws_iam_policy_document.s3_gateway_endpoint.json

  tags = { Name = "${var.project_name}-${var.environment}-s3-gateway-endpoint" }
}

resource "aws_s3_bucket" "erp_documents" {
  bucket = "${var.project_name}-${var.environment}-erp-documents-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  # The academic teardown must remove all private demo files and every object version.
  force_destroy = true
  tags = {
    Name      = "${var.project_name}-${var.environment}-erp-documents"
    Component = "erp-documents"
  }
}

resource "aws_s3_bucket_public_access_block" "erp_documents" {
  bucket                  = aws_s3_bucket.erp_documents.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "erp_documents" {
  bucket = aws_s3_bucket.erp_documents.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "erp_documents" {
  bucket = aws_s3_bucket.erp_documents.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "erp_documents" {
  bucket = aws_s3_bucket.erp_documents.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_cors_configuration" "erp_documents" {
  count  = var.intranet_web_origin == "" ? 0 : 1
  bucket = aws_s3_bucket.erp_documents.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT"]
    allowed_origins = [var.intranet_web_origin]
    expose_headers  = ["ETag", "x-amz-version-id"]
    max_age_seconds = 1800
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "erp_documents" {
  bucket = aws_s3_bucket.erp_documents.id
  rule {
    id     = "expire-old-document-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

data "aws_iam_policy_document" "erp_documents_transport" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.erp_documents.arn,
      "${aws_s3_bucket.erp_documents.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "erp_documents_transport" {
  bucket = aws_s3_bucket.erp_documents.id
  policy = data.aws_iam_policy_document.erp_documents_transport.json
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

resource "aws_cloudwatch_log_group" "erp" {
  name              = "/aws/lambda/${local.erp_name}"
  retention_in_days = 3
}

resource "aws_lambda_function" "api" {
  function_name                  = local.api_name
  role                           = aws_iam_role.api.arn
  runtime                        = "nodejs22.x"
  handler                        = "lambda.handler"
  filename                       = "${path.module}/../../../api/dist/catalog-api-v2.zip"
  source_code_hash               = filebase64sha256("${path.module}/../../../api/dist/catalog-api-v2.zip")
  memory_size                    = 256
  timeout                        = 10
  architectures                  = ["x86_64"]
  reserved_concurrent_executions = 10

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

  depends_on = [aws_cloudwatch_log_group.api, aws_iam_role_policy.api, aws_iam_role_policy.vpc_logs]
}

resource "aws_lambda_function" "bootstrap" {
  function_name                  = local.bootstrap_name
  role                           = aws_iam_role.bootstrap.arn
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
      DB_MASTER_SECRET_ARN            = aws_db_instance.norcom.master_user_secret[0].secret_arn
      DB_CATALOG_SECRET_ARN           = aws_secretsmanager_secret.catalog_reader.arn
      DB_INQUIRY_SECRET_ARN           = aws_secretsmanager_secret.inquiry_writer.arn
      DB_ERP_SECRET_ARN               = aws_secretsmanager_secret.erp_runtime.arn
      DB_INITIALIZE_DEMO_SCHEMA       = "true"
      DB_SCHEMA_FILE                  = local.bootstrap_asset_paths[0]
      DB_MIGRATION_FILE               = local.bootstrap_asset_paths[1]
      DB_SEED_FILE                    = local.bootstrap_asset_paths[2]
      DB_ERP_MIGRATION_FILE           = local.erp_migration_path
      DB_ERP_FINANCIAL_MIGRATION_FILE = local.erp_financial_migration_path
      DB_ERP_DOCUMENT_MIGRATION_FILE  = local.erp_document_migration_path
      PGHOST                          = aws_db_instance.norcom.address
      PGPORT                          = tostring(aws_db_instance.norcom.port)
      PGDATABASE                      = aws_db_instance.norcom.db_name
      NODE_EXTRA_CA_CERTS             = "/var/runtime/ca-cert.pem"
    }
  }

  depends_on = [aws_cloudwatch_log_group.bootstrap, aws_iam_role_policy.bootstrap, aws_iam_role_policy.vpc_logs]
}

resource "aws_lambda_function" "inquiries" {
  function_name                  = local.inquiry_name
  role                           = aws_iam_role.inquiries.arn
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

  depends_on = [aws_cloudwatch_log_group.inquiries, aws_iam_role_policy.inquiries, aws_iam_role_policy.vpc_logs]
}

resource "aws_lambda_function" "erp" {
  function_name                  = local.erp_name
  role                           = aws_iam_role.erp.arn
  runtime                        = "nodejs22.x"
  handler                        = "erp-lambda/lambda.handler"
  filename                       = "${path.module}/../../../api/dist/erp-api-v1.zip"
  source_code_hash               = filebase64sha256("${path.module}/../../../api/dist/erp-api-v1.zip")
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
      DB_ERP_SECRET_ARN           = aws_secretsmanager_secret.erp_runtime.arn
      INTRANET_SESSION_SECRET_ARN = aws_secretsmanager_secret.erp_session_signing.arn
      INTRANET_WEB_ORIGIN         = var.intranet_web_origin
      PGHOST                      = aws_db_instance.norcom.address
      PGPORT                      = tostring(aws_db_instance.norcom.port)
      PGDATABASE                  = aws_db_instance.norcom.db_name
      PG_POOL_MAX                 = "1"
      NODE_EXTRA_CA_CERTS         = "/var/runtime/ca-cert.pem"
      ERP_DOCUMENT_BUCKET         = aws_s3_bucket.erp_documents.bucket
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.erp,
    aws_iam_role_policy.erp,
    aws_iam_role_policy.vpc_logs,
    aws_secretsmanager_secret_version.erp_session_signing,
  ]
}

resource "aws_apigatewayv2_api" "catalog" {
  name          = "${var.project_name}-${var.environment}-catalog"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = distinct([var.web_origin, var.intranet_web_origin])
    allow_methods     = ["GET", "POST", "PATCH"]
    allow_headers     = ["content-type"]
    allow_credentials = true
    max_age           = 300
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

resource "aws_apigatewayv2_integration" "erp_lambda" {
  api_id                 = aws_apigatewayv2_api.catalog.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.erp.invoke_arn
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

resource "aws_apigatewayv2_route" "erp_staff" {
  api_id    = aws_apigatewayv2_api.catalog.id
  route_key = "ANY /erp-api/v1/staff/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.erp_lambda.id}"
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

resource "aws_lambda_permission" "api_gateway_erp" {
  statement_id  = "AllowHttpApiInvokeInternalErp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.erp.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.catalog.execution_arn}/*/*"
}
