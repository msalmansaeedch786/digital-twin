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

variable "amplify_domain" {
  description = "The Amplify frontend domain (e.g. main.xxxxx.amplifyapp.com) — used for CORS allow_origins"
  type        = string
  # Set in terraform.tfvars or via TF_VAR_amplify_domain env var
  # DO NOT commit real domain to version control if it changes per env
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
  # Set in terraform.tfvars: alert_email = "your@email.com"
  # After apply, confirm the SNS subscription from your inbox
}
