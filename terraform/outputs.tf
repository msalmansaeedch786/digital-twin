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

output "custom_domain_cert_validation_record" {
  description = "ACM validation CNAME to add at the domain provider (is-a.dev) to issue the SSL cert"
  value       = var.custom_domain == "" ? null : aws_amplify_domain_association.custom[0].certificate_verification_dns_record
}

output "custom_domain_sub_domains" {
  description = "Sub-domain CNAME record(s) mapping the custom domain to the Amplify app"
  value       = var.custom_domain == "" ? null : aws_amplify_domain_association.custom[0].sub_domain
}
