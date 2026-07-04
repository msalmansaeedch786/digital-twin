# ===========================================================================
# Outputs — Safe Exports
# ===========================================================================

output "frontend_url" {
  description = "The public URL for the Digital Twin Frontend Application"
  value       = "https://${replace(aws_amplify_branch.feature.branch_name, "/", "-")}.${aws_amplify_app.frontend.default_domain}"
}
