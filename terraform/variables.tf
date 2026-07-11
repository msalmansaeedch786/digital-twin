variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "digital-twin"
}

variable "project_name" {
  description = "Name of the project, used for naming and tagging all resources"
  type        = string
  default     = "digital-twin"
}

variable "github_token" {
  description = "GitHub Personal Access Token for Amplify to access the repo"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
  default     = "alerts@example.com" # Dummy email. Override via TF_VAR_alert_email in production.
}

variable "git_branch" {
  description = "The Git branch this infrastructure is deployed from. Used for OIDC trust, Amplify branch, and CORS locking."
  type        = string
  default     = "main"
}

variable "custom_domain" {
  description = "Custom domain to attach to the Amplify app (e.g. salman-twin.is-a.dev). Empty string disables the custom-domain association."
  type        = string
  default     = "salman-twin.is-a.dev"
}
