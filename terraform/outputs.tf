# ===========================================================================
# Outputs — Safe Exports
# ===========================================================================

output "frontend_url" {
  description = "The public URL for the Digital Twin Frontend Application"
  value       = "https://${replace(aws_amplify_branch.feature.branch_name, "/", "-")}.${aws_amplify_app.frontend.default_domain}"
}

output "api_gateway_url" {
  description = "Base invoke URL of the HTTP API (used by the frontend NEXT_PUBLIC_API_URL)"
  value       = aws_apigatewayv2_stage.prod.invoke_url
}

output "s3_bucket_name" {
  description = "Name of the knowledge-base S3 bucket (consumed by the data_sync workflow)"
  value       = aws_s3_bucket.knowledge_base.bucket
}
