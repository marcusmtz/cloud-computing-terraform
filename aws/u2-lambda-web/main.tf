terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region              = "us-east-2"
  allowed_account_ids = [var.expected_aws_account_id]
  default_tags { tags = { Project = "norcom", Environment = "u2", ManagedBy = "Terraform" } }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "norcom-u2-web-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.web.arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "norcom-u2-web-logs"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/aws/lambda/norcom-u2-web"
  retention_in_days = 3
}

resource "aws_lambda_function" "web" {
  function_name                  = "norcom-u2-web"
  role                           = aws_iam_role.web.arn
  runtime                        = "nodejs22.x"
  handler                        = "index.handler"
  filename                       = "${path.module}/web.zip"
  source_code_hash               = filebase64sha256("${path.module}/web.zip")
  memory_size                    = 128
  timeout                        = 3
  reserved_concurrent_executions = 1
  depends_on                     = [aws_iam_role_policy.logs]
}

resource "aws_lambda_function_url" "web" {
  function_name      = aws_lambda_function.web.function_name
  authorization_type = "NONE"
  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_lambda_permission" "function_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.web.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "invoke" {
  statement_id             = "AllowInvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.web.function_name
  principal                = "*"
  invoked_via_function_url = true
}

output "web_url" { value = aws_lambda_function_url.web.function_url }
