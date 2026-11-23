data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "${var.project_name}-${var.environment}-catalog-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "bootstrap" {
  name               = "${var.project_name}-${var.environment}-catalog-bootstrap-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "inquiries" {
  name               = "${var.project_name}-${var.environment}-public-inquiries-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "erp" {
  name               = "${var.project_name}-${var.environment}-erp-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "recovery_validation" {
  count              = var.recovery_test_enabled ? 1 : 0
  name               = "${var.project_name}-${var.environment}-restore-check-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

locals {
  lambda_role_names = merge({
    api       = aws_iam_role.api.name
    erp       = aws_iam_role.erp.name
    bootstrap = aws_iam_role.bootstrap.name
    inquiries = aws_iam_role.inquiries.name
    }, var.recovery_test_enabled ? {
    recovery_validation = aws_iam_role.recovery_validation[0].name
  } : {})
  lambda_function_arns = merge({
    api       = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.api_name}"
    erp       = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.erp_name}"
    bootstrap = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.bootstrap_name}"
    inquiries = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.inquiry_name}"
    }, var.recovery_test_enabled ? {
    recovery_validation = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-${var.environment}-restore-check"
  } : {})
  lambda_log_arns = merge({
    api       = aws_cloudwatch_log_group.api.arn
    erp       = aws_cloudwatch_log_group.erp.arn
    bootstrap = aws_cloudwatch_log_group.bootstrap.arn
    inquiries = aws_cloudwatch_log_group.inquiries.arn
    }, var.recovery_test_enabled ? {
    recovery_validation = aws_cloudwatch_log_group.recovery_validation[0].arn
  } : {})
}

data "aws_iam_policy_document" "vpc_logs" {
  for_each = local.lambda_log_arns

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${each.value}:*"]
  }
  statement {
    sid = "ManageLambdaNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]
  }
  statement {
    sid    = "DenyFunctionCodeManagingVpcInterfaces"
    effect = "Deny"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DetachNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "lambda:SourceFunctionArn"
      values   = [local.lambda_function_arns[each.key]]
    }
  }
}

resource "aws_iam_role_policy" "vpc_logs" {
  for_each = local.lambda_role_names
  name     = "${var.project_name}-${var.environment}-${each.key}-vpc-logs"
  role     = each.value
  policy   = data.aws_iam_policy_document.vpc_logs[each.key].json
}

data "aws_iam_policy_document" "api_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.catalog_reader.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.secrets_manager.id]
    }
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "${var.project_name}-${var.environment}-api-secret-read"
  role   = aws_iam_role.api.name
  policy = data.aws_iam_policy_document.api_secret.json
}

data "aws_iam_policy_document" "inquiries_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.inquiry_writer.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.secrets_manager.id]
    }
  }
}

data "aws_iam_policy_document" "erp_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.erp_runtime.arn,
      aws_secretsmanager_secret.erp_session_signing.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.secrets_manager.id]
    }
  }
}

data "aws_iam_policy_document" "erp_documents" {
  statement {
    sid       = "ReadAndStorePrivateDocuments"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.erp_documents.arn}/*"]
  }
}

resource "aws_iam_role_policy" "erp_documents" {
  name   = "${var.project_name}-${var.environment}-erp-documents"
  role   = aws_iam_role.erp.name
  policy = data.aws_iam_policy_document.erp_documents.json
}

resource "aws_iam_role_policy" "erp" {
  name   = "${var.project_name}-${var.environment}-erp-secret-read"
  role   = aws_iam_role.erp.name
  policy = data.aws_iam_policy_document.erp_secrets.json
}

resource "aws_iam_role_policy" "inquiries" {
  name   = "${var.project_name}-${var.environment}-inquiries-secret-read"
  role   = aws_iam_role.inquiries.name
  policy = data.aws_iam_policy_document.inquiries_secret.json
}

data "aws_iam_policy_document" "bootstrap_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.norcom.master_user_secret[0].secret_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.secrets_manager.id]
    }
  }
  statement {
    actions = ["secretsmanager:PutSecretValue"]
    resources = [
      aws_secretsmanager_secret.catalog_reader.arn,
      aws_secretsmanager_secret.inquiry_writer.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.secrets_manager.id]
    }
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
    resources = [aws_secretsmanager_secret.erp_runtime.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.secrets_manager.id]
    }
  }
}

resource "aws_iam_role_policy" "bootstrap" {
  name   = "${var.project_name}-${var.environment}-bootstrap-secrets"
  role   = aws_iam_role.bootstrap.name
  policy = data.aws_iam_policy_document.bootstrap_secrets.json
}

data "aws_iam_policy_document" "recovery_validation_secret" {
  count = var.recovery_test_enabled ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.recovery_validation[0].master_user_secret[0].secret_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.secrets_manager.id]
    }
  }
}

resource "aws_iam_role_policy" "recovery_validation_secret" {
  count  = var.recovery_test_enabled ? 1 : 0
  name   = "${var.project_name}-${var.environment}-restore-check-secret"
  role   = aws_iam_role.recovery_validation[0].name
  policy = data.aws_iam_policy_document.recovery_validation_secret[0].json
}
