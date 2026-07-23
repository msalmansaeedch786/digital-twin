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
  description = "Only needed when (re)creating the Amplify app: a one-time setup token from the Amplify GitHub App flow (or a classic PAT). Normal runs use the GitHub App connection and leave this unset."
  type        = string
  sensitive   = true
  default     = null
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

# PAUSED 2026-07-23. salman-twin.is-a.dev was removed from the is-a.dev registry
# by maintainer cleanup PR is-a-dev/register#44406 ("remove disconnected domains"),
# which deletes subdomains that don't resolve to a working site because a dangling
# record is hijackable. The Amplify association never reached HEALTHY: each failed
# certificate forces a re-add, and every re-add hands out a fresh CloudFront
# address, which needs another registry PR — a loop we chose to stop rather than
# keep feeding. The app is served on its default *.amplifyapp.com URL meanwhile.
# To re-enable: get the domain restored (comment on #44406), then set this back to
# "salman-twin.is-a.dev" and publish BOTH the routing CNAME and the ACM validation
# record in a single registry PR before the association's validation window lapses.
variable "custom_domain" {
  description = "Custom domain to attach to the Amplify app (e.g. salman-twin.is-a.dev). Empty string disables the custom-domain association."
  type        = string
  default     = ""
}

variable "bedrock_llm_model_id" {
  description = "Bedrock model id (inference profile) for chat generation. Single source of truth: feeds the Lambda env var and the IAM invoke policy."
  type        = string
  default     = "eu.amazon.nova-lite-v1:0"
}

variable "bedrock_embedding_model_id" {
  description = "Bedrock model id for embeddings. Single source of truth: feeds both Lambdas' env vars and the IAM invoke policies."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD — email alerts fire at 80% actual and 100% forecasted. Tracks GROSS usage (credits excluded) so it is live even while free credits apply."
  type        = number
  default     = 45
}

variable "abuse_request_threshold_1m" {
  description = "API Gateway requests per MINUTE that count as a flood (needs 2 consecutive minutes to alarm + trip the circuit breaker). A real visitor produces < 20/min; the 5 req/s throttle admits at most 300/min."
  type        = number
  default     = 150
}

variable "anomaly_alert_threshold_usd" {
  description = "Cost Anomaly Detection: email when a detected anomaly's dollar impact is at least this much above the normal spend pattern. AWS only flags statistically unusual spend, so very low values mostly add noise; ~1 USD is the practical floor."
  type        = number
  default     = 1
}

variable "daily_budget_usd" {
  description = "Daily cost tripwire in USD (gross usage, credits excluded). Expected steady-state is ~1.50/day after the single-AZ endpoint + no-X-Ray trim; 2.00 leaves headroom so normal lumpy days do not false-alarm."
  type        = number
  default     = 2
}

variable "anomaly_monitor_arn" {
  description = "ARN of the account's existing dimensional (by-service) Cost Anomaly monitor. AWS allows only one per account and auto-creates 'Default-Services-Monitor'; we attach our subscription to it rather than create a duplicate."
  type        = string
  default     = "arn:aws:ce::231740516864:anomalymonitor/9d0580f9-94ab-44f8-a5b7-72e23652d0db"
}
