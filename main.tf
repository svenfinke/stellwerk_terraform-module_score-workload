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
  image_uri     = var.container_image
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
    variables = var.environment_variables
  }

  # Container image overrides (if provided)
  dynamic "image_config" {
    for_each = (var.container_command != null || var.container_args != null) ? [1] : []
    content {
      entry_point = var.container_command
      command     = var.container_args
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
