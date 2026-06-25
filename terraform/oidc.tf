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
              "repo:msalmansaeedch786/digital-twin:ref:refs/heads/feature/aws-enterprise-migration",
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
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "github_actions_policy" {
  name        = "${var.project_name}-github-actions-policy"
  description = "Permissions for GitHub Actions to deploy Terraform infrastructure"

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
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/digital-twin-terraform-locks"
        ]
      },
      {
        Sid    = "InfrastructureManagement"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "rds:*",
          "lambda:*",
          "apigateway:*",
          "s3:*",
          "iam:*",
          "logs:*",
          "events:*",
          "secretsmanager:*",
          "cloudtrail:*",
          "sns:*",
          "cloudwatch:*",
          "kms:*",
          "xray:*",
          "bedrock:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "The IAM Role ARN for GitHub Actions OIDC"
}
