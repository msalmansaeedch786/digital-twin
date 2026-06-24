# ===========================================================================
# Outputs — Export values needed to wire services together
# ===========================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (for Lambda and RDS)"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS PostgreSQL instance"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the RDS master password"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "s3_bucket_name" {
  description = "The name of the S3 knowledge base bucket"
  value       = aws_s3_bucket.knowledge_base.id
}

output "lambda_security_group_id" {
  description = "The security group ID for Lambda functions"
  value       = aws_security_group.lambda.id
}

output "lambda_role_arn" {
  description = "The ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_exec.arn
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.main.api_endpoint
  description = "The HTTP API Gateway URL"
}
