# Derive container config from either the Score `containers` map or direct vars.
# `containers` takes precedence — only the first container is used (Lambda is single-container).
locals {
  _first_container  = length(var.containers) > 0 ? values(var.containers)[0] : null
  container_image   = local._first_container != null ? local._first_container.image : var.container_image
  container_command = local._first_container != null ? try(local._first_container.command, null) : var.container_command
  container_args    = local._first_container != null ? try(local._first_container.args, null) : var.container_args
  # Merge Score-defined variables with any additional environment_variables input
  all_env_vars = merge(
    local._first_container != null ? try(local._first_container.variables, {}) : {},
    var.environment_variables,
  )
}

# CloudWatch Log Group for Lambda function output
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "lambda-${var.function_name}"
    }
  )
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.function_name}-execution-role"
    }
  )
}

# IAM policy for CloudWatch Logs
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${var.function_name}-logs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# Lambda function with container image
resource "aws_lambda_function" "workload" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_role.arn
  image_uri     = local.container_image
  package_type  = "Image"

  # Execution configuration
  timeout     = var.timeout
  memory_size = var.memory_size
  ephemeral_storage {
    size = var.ephemeral_storage_size
  }
  architectures = var.architectures

  # Environment variables from resolved resources + custom vars
  environment {
    variables = local.all_env_vars
  }

  # Container image overrides (if provided)
  dynamic "image_config" {
    for_each = (local.container_command != null || local.container_args != null) ? [1] : []
    content {
      entry_point = local.container_command
      command     = local.container_args
    }
  }

  # Explicit log group dependency to ensure it's created first
  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_logs
  ]

  tags = merge(
    var.tags,
    {
      Name = var.function_name
    }
  )
}
