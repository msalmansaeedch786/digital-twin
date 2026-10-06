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

# msalmansaeedch.de is a self-owned domain registered at Porkbun, replacing the
# earlier free salman-twin.is-a.dev subdomain. That is-a.dev attempt was abandoned
# (removed by registry cleanup PR is-a-dev/register#44406) because its DNS could
# only be changed by a human-merged pull request, which could never keep up with
# Amplify's ordered, time-limited certificate-validation records. Owning the DNS
# fixes that at the root: the ACM validation and routing records are written
# directly (Porkbun API), so validation completes in minutes and cannot be pruned
# by a third party. Empty string disables the custom-domain association.
variable "custom_domain" {
  description = "Custom domain to attach to the Amplify app (e.g. msalmansaeedch.de). Empty string disables the custom-domain association."
  type        = string
  default     = "msalmansaeedch.de"
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
  # Was 45, sized for a stack burning ~$1.14/day on RDS + VPC endpoints. After
  # those were deleted (5 Oct 2026) the idle rate is $0.0006/day and the heaviest
  # realistic month — 5,000 chats plus 50 deploys — is about $2. A $45 ceiling
  # would need spending to rise 2,000-fold before saying anything, which is
  # decoration rather than a guard: it feels like protection while being incapable
  # of firing. $5 keeps roughly 2.5x headroom over the heavy case.
  default = 5
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
  description = "Daily cost tripwire in USD (gross usage, credits excluded). Idle is ~$0.0006/day; 0.50 catches an accidentally recreated database on its first day without false-alarming on a heavy build day."
  type        = number
  # Chosen against the failure mode that actually matters. The expensive mistake
  # here is re-creating something that bills by the hour: a db.t4g.micro is
  # $0.54/day and a single interface VPC endpoint is $0.29/day. At 0.50 the
  # database trips this on day one. A busy development day is about $0.15, almost
  # all of it Amplify build minutes, so it stays comfortably clear.
  default = 0.50
}

variable "anomaly_monitor_arn" {
  description = "ARN of the account's existing dimensional (by-service) Cost Anomaly monitor. AWS allows only one per account and auto-creates 'Default-Services-Monitor'; we attach our subscription to it rather than create a duplicate."
  type        = string
  default     = "arn:aws:ce::231740516864:anomalymonitor/9d0580f9-94ab-44f8-a5b7-72e23652d0db"
}

variable "vector_index_name" {
  description = "Name of the S3 Vectors index holding the knowledge-base chunks"
  type        = string
  # Was the pgvector collection name; kept identical so logs and docs that refer
  # to "digital_twin_docs" still mean the same thing. Dots and hyphens only —
  # S3 Vectors index names reject underscores.
  default = "digital-twin-docs"
}
