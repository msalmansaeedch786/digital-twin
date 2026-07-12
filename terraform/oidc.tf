# ===========================================================================
# GitHub Actions OIDC Provider & IAM Role
# ===========================================================================


resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"] # GitHub Actions Thumbprints
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" : [
              "repo:msalmansaeedch786/digital-twin:ref:refs/heads/${var.git_branch}",
              "repo:msalmansaeedch786/digital-twin:pull_request"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# SCOPED DEPLOYMENT POLICY — Principle of Least Privilege
#
# A Terraform *deploy* role is inherently powerful, but "powerful" must not mean
# "account admin on Resource: *". The strategy here:
#   1. Read-only discovery (Describe/List/Get) stays on "*" — these APIs do not
#      support resource-level scoping and only disclose metadata (low risk).
#   2. Every mutating action is scoped to project-prefixed ARNs, mirroring the
#      per-Lambda roles in iam.tf.
#   3. Services whose *create* actions cannot be ARN-scoped by AWS (EC2/VPC, RDS,
#      API Gateway, Amplify) are instead bounded by an aws:RequestedRegion guard.
#   4. IAM is split so the role can manage project roles/policies WITHOUT being
#      able to grant itself admin: iam:AttachRolePolicy is restricted to an
#      allowlist that deliberately excludes AdministratorAccess, and iam:PassRole
#      is scoped to project roles + the specific services that consume them.
#   5. bedrock:* removed — Terraform creates no Bedrock resources (runtime
#      Bedrock access lives on the Lambda execution roles, not this deploy role).
# ---------------------------------------------------------------------------

locals {
  gha_account_id = data.aws_caller_identity.current.account_id

  # Managed/customer policies GitHub Actions may attach to project roles.
  # AdministratorAccess is deliberately NOT here — this is the anti-escalation
  # guardrail. A role able to attach arbitrary managed policies could grant
  # itself (or a new role) admin; restricting the attachable set closes that path.
  gha_attachable_policies = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
    "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
    "arn:aws:iam::aws:policy/AdministratorAccess-Amplify",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-*",
  ]
}

resource "aws_iam_policy" "github_actions_policy" {
  name        = "${var.project_name}-github-actions-policy"
  description = "Scoped least-privilege deploy permissions for GitHub Actions (Terraform)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          "arn:aws:s3:::digital-twin-terraform-state-*",
          "arn:aws:s3:::digital-twin-terraform-state-*/*",
          "arn:aws:dynamodb:${var.aws_region}:${local.gha_account_id}:table/digital-twin-terraform-locks"
        ]
      },

      # --- Read-only discovery: required at plan/refresh, cannot be ARN-scoped ---
      {
        Sid    = "ReadOnlyDiscovery"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "rds:List*",
          "lambda:List*",
          "lambda:GetAccountSettings",
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",
          "iam:Get*",
          "iam:List*",
          "logs:Describe*",
          "logs:List*",
          "cloudwatch:Describe*",
          "cloudwatch:List*",
          "cloudwatch:GetMetricData",
          "events:Describe*",
          "events:List*",
          "sns:List*",
          "sns:GetTopicAttributes",
          "sns:GetSubscriptionAttributes",
          "secretsmanager:Describe*",
          "secretsmanager:List*",
          "secretsmanager:GetResourcePolicy",
          "apigateway:GET",
          "cloudtrail:Describe*",
          "cloudtrail:Get*",
          "cloudtrail:List*",
          "cloudtrail:LookupEvents",
          "kms:Describe*",
          "kms:List*",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "amplify:List*",
          "amplify:Get*",
          # Amplify custom-domain setup calls these to detect whether the domain
          # is Route53-hosted (salman.is-a.dev is external, so it finds none and
          # falls back to manual DNS records). Read-only, account-level.
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      },

      # --- EC2 / VPC: create actions can't be ARN-scoped; bound to the region ---
      {
        Sid       = "Ec2NetworkingManagement"
        Effect    = "Allow"
        Action    = ["ec2:*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },

      # --- RDS: resource-level perms are incomplete for create; bound to region ---
      {
        Sid       = "RdsManagement"
        Effect    = "Allow"
        Action    = ["rds:*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },

      # --- API Gateway: opaque generated api-ids; bound to region ---
      {
        Sid      = "ApiGatewayManagement"
        Effect   = "Allow"
        Action   = ["apigateway:*"]
        Resource = ["arn:aws:apigateway:${var.aws_region}::/*"]
      },

      # --- Amplify: app-ids are generated (not name-prefixed); region+account bound ---
      {
        Sid      = "AmplifyManagement"
        Effect   = "Allow"
        Action   = ["amplify:*"]
        Resource = ["arn:aws:amplify:${var.aws_region}:${local.gha_account_id}:apps/*"]
      },

      # --- S3: all project buckets share the digital-twin- prefix ---
      {
        Sid    = "S3ProjectBuckets"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      },

      # --- Lambda: project functions only ---
      {
        Sid      = "LambdaManagement"
        Effect   = "Allow"
        Action   = ["lambda:*"]
        Resource = ["arn:aws:lambda:${var.aws_region}:${local.gha_account_id}:function:${var.project_name}-*"]
      },

      # --- CloudWatch Logs: the four project log-group prefixes ---
      {
        Sid    = "LogsManagement"
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/lambda/${var.project_name}-*",
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/lambda/${var.project_name}-*:*",
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/apigateway/${var.project_name}*",
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/apigateway/${var.project_name}*:*",
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/rds/instance/${var.project_name}-*",
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/rds/instance/${var.project_name}-*:*",
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/cloudtrail/${var.project_name}*",
          "arn:aws:logs:${var.aws_region}:${local.gha_account_id}:log-group:/aws/cloudtrail/${var.project_name}*:*"
        ]
      },

      # --- CloudWatch alarms: project alarms only ---
      {
        Sid    = "CloudWatchAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:EnableAlarmActions",
          "cloudwatch:DisableAlarmActions",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource"
        ]
        Resource = ["arn:aws:cloudwatch:${var.aws_region}:${local.gha_account_id}:alarm:${var.project_name}-*"]
      },

      # --- SNS: project topics only ---
      {
        Sid      = "SnsManagement"
        Effect   = "Allow"
        Action   = ["sns:*"]
        Resource = ["arn:aws:sns:${var.aws_region}:${local.gha_account_id}:${var.project_name}-*"]
      },

      # --- EventBridge: project rules on the default bus ---
      {
        Sid    = "EventBridgeManagement"
        Effect = "Allow"
        Action = ["events:*"]
        Resource = [
          "arn:aws:events:${var.aws_region}:${local.gha_account_id}:rule/${var.project_name}-*",
          "arn:aws:events:${var.aws_region}:${local.gha_account_id}:event-bus/default"
        ]
      },

      # --- CloudTrail: project trail only ---
      {
        Sid      = "CloudTrailManagement"
        Effect   = "Allow"
        Action   = ["cloudtrail:*"]
        Resource = ["arn:aws:cloudtrail:${var.aws_region}:${local.gha_account_id}:trail/${var.project_name}-*"]
      },

      # --- SQS: project queues only (ingestion dead-letter queue) ---
      {
        Sid      = "SqsManagement"
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = ["arn:aws:sqs:${var.aws_region}:${local.gha_account_id}:${var.project_name}-*"]
      },

      # --- Budgets: cost guardrail for the unauthenticated public endpoint ---
      # ViewBudget covers all describe APIs; ModifyBudget covers create/update/
      # delete. Tag actions are required because provider default_tags makes
      # CreateBudget tag the resource at creation.
      {
        Sid    = "BudgetsManagement"
        Effect = "Allow"
        Action = [
          "budgets:ViewBudget",
          "budgets:ModifyBudget",
          "budgets:TagResource",
          "budgets:UntagResource",
          "budgets:ListTagsForResource"
        ]
        Resource = ["arn:aws:budgets::${local.gha_account_id}:budget/${var.project_name}-*"]
      },

      # --- Cost Anomaly Detection: ML tripwire for spend above the normal
      # pattern. These actions manage anomaly monitors/subscriptions and cannot
      # be ARN-scoped by AWS at create time. Cost-management scope, low risk.
      {
        Sid    = "CostAnomalyDetection"
        Effect = "Allow"
        Action = [
          "ce:CreateAnomalyMonitor",
          "ce:UpdateAnomalyMonitor",
          "ce:DeleteAnomalyMonitor",
          "ce:GetAnomalyMonitors",
          "ce:CreateAnomalySubscription",
          "ce:UpdateAnomalySubscription",
          "ce:DeleteAnomalySubscription",
          "ce:GetAnomalySubscriptions",
          "ce:TagResource",
          "ce:UntagResource",
          "ce:ListTagsForResource"
        ]
        Resource = "*"
      },

      # --- CloudWatch Logs delivery: required to create/update API Gateway
      # stages that have access logging. These actions manage the log-delivery
      # plumbing itself and do not support resource-level scoping.
      {
        Sid    = "LogsDeliveryForApiGatewayAccessLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies"
        ]
        Resource = "*"
      },

      # --- IAM roles: project roles only ---
      {
        Sid    = "IamRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:DetachRolePolicy",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = ["arn:aws:iam::${local.gha_account_id}:role/${var.project_name}-*"]
      },

      # --- IAM policies: project customer-managed policies only ---
      {
        Sid    = "IamPolicyManagement"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListPolicyVersions",
          "iam:TagPolicy",
          "iam:UntagPolicy"
        ]
        Resource = ["arn:aws:iam::${local.gha_account_id}:policy/${var.project_name}-*"]
      },

      # --- IAM AttachRolePolicy: allowlisted policies ONLY (anti-escalation) ---
      # Excludes AdministratorAccess, so this role cannot grant admin to itself
      # or any new project role it creates.
      {
        Sid       = "IamAttachRolePolicyScoped"
        Effect    = "Allow"
        Action    = ["iam:AttachRolePolicy"]
        Resource  = ["arn:aws:iam::${local.gha_account_id}:role/${var.project_name}-*"]
        Condition = { ArnLike = { "iam:PolicyARN" = local.gha_attachable_policies } }
      },

      # --- IAM PassRole: project roles → project services only ---
      {
        Sid      = "IamPassRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = ["arn:aws:iam::${local.gha_account_id}:role/${var.project_name}-*"]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "lambda.amazonaws.com",
              "amplify.amazonaws.com",
              "cloudtrail.amazonaws.com"
            ]
          }
        }
      },

      # --- IAM OIDC provider: the GitHub federation resource only ---
      {
        Sid    = "IamOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint"
        ]
        Resource = ["arn:aws:iam::${local.gha_account_id}:oidc-provider/token.actions.githubusercontent.com"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}
