output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.workload.arn
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.workload.function_name
}

output "function_role_arn" {
  description = "IAM execution role ARN"
  value       = aws_iam_role.lambda_role.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "log_group_arn" {
  description = "CloudWatch Log Group ARN"
  value       = aws_cloudwatch_log_group.lambda.arn
}
