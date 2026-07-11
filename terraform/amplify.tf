# ===========================================================================
# AWS Amplify — Frontend Hosting
# ===========================================================================

# IAM Role for Amplify to log to CloudWatch and manage SSR
resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_admin" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

resource "aws_amplify_app" "frontend" {
  name       = "${var.project_name}-frontend"
  repository = "https://github.com/msalmansaeedch786/digital-twin"

  # The GitHub PAT is required so AWS can automatically pull code when you push
  access_token = var.github_token

  iam_service_role_arn = aws_iam_role.amplify_role.arn
  platform             = "WEB_COMPUTE" # Required for Next.js SSR

  # Next.js 14 Build Specification
  build_spec = <<-EOT
    version: 1
    applications:
      - frontend:
          phases:
            preBuild:
              commands:
                - npm ci --cache .npm --prefer-offline
            build:
              commands:
                - npm run build
          artifacts:
            baseDirectory: .next
            files:
              - '**/*'
          cache:
            paths:
              - .next/cache/**/*
              - .npm/**/*
        appRoot: frontend
  EOT

  # Environment variables injected directly into the frontend build
  environment_variables = {
    AMPLIFY_MONOREPO_APP_ROOT = "frontend"
    AMPLIFY_DIFF_DEPLOY       = "false"
  }

  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "404-200"
  }
}

resource "aws_amplify_branch" "feature" {
  app_id            = aws_amplify_app.frontend.id
  branch_name       = var.git_branch
  enable_auto_build = true
  framework         = "Next.js - SSR"

  # Environment variables specific to the branch (breaks the API Gateway cycle)
  environment_variables = {
    NEXT_PUBLIC_API_URL = aws_apigatewayv2_stage.prod.invoke_url
  }
}

# Custom domain (e.g. salman.is-a.dev). The DNS records are hosted by the
# domain provider (is-a.dev, via PR), so we DON'T wait for verification here —
# otherwise `terraform apply` would block until the records are added manually.
# After apply, read the required records with:
#   aws amplify get-domain-association --app-id <id> --domain-name <domain>
resource "aws_amplify_domain_association" "custom" {
  count       = var.custom_domain == "" ? 0 : 1
  app_id      = aws_amplify_app.frontend.id
  domain_name = var.custom_domain

  wait_for_verification = false

  sub_domain {
    branch_name = aws_amplify_branch.feature.branch_name
    prefix      = "" # map the domain apex itself (salman.is-a.dev)
  }
}

# Automatically trigger a build when a new branch is created
resource "terraform_data" "trigger_amplify_build" {
  triggers_replace = [
    aws_amplify_branch.feature.arn
  ]

  provisioner "local-exec" {
    command = "aws amplify start-job --app-id ${aws_amplify_app.frontend.id} --branch-name ${aws_amplify_branch.feature.branch_name} --job-type RELEASE --region ${var.aws_region}"
  }
}
