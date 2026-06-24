# ===========================================================================
# IAM — Lambda Execution Roles with Least Privilege
# AWS Best Practice: Separate roles per Lambda function
# Each function gets ONLY the permissions it actually needs
# Ref: AWS Well-Architected Security Pillar — Identity & Access Management
# ===========================================================================

# ---------------------------------------------------------------------------
# SHARED: Base assume-role policy for Lambda
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# API LAMBDA ROLE — Minimum permissions for the chat API
# Needs: Bedrock (invoke), Secrets Manager (read DB password), CloudWatch Logs, X-Ray, VPC
# Does NOT need: S3 write
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda_api" {
  name               = "${var.project_name}-lambda-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "api_basic" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "api_vpc" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "api_xray" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_policy" "lambda_api_custom" {
  name        = "${var.project_name}-lambda-api-policy"
  description = "Least-privilege policy for the API Lambda: Bedrock + Secrets Manager (read only)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerReadAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_db_instance.postgres.master_user_secret[0].secret_arn
        ]
      },
      {
        Sid    = "BedrockInvokeAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/meta.llama3-1-8b-instruct-v1:0"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_custom" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = aws_iam_policy.lambda_api_custom.arn
}

# ---------------------------------------------------------------------------
# INGESTION LAMBDA ROLE — Permissions for the data ingestion pipeline
# Needs: S3 (read + delete objects), Bedrock (embeddings only), Secrets Manager, VPC, X-Ray
# Does NOT need: Bedrock LLM (only embeddings), S3 write to deployment bucket
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda_ingestion" {
  name               = "${var.project_name}-lambda-ingestion-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ingestion_basic" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ingestion_vpc" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ingestion_xray" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_policy" "lambda_ingestion_custom" {
  name        = "${var.project_name}-lambda-ingestion-policy"
  description = "Least-privilege policy for the Ingestion Lambda: S3 read/delete + Bedrock embeddings + Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadDeleteAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      },
      {
        Sid    = "SecretsManagerReadAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_db_instance.postgres.master_user_secret[0].secret_arn
        ]
      },
      {
        # Ingestion only needs embeddings, NOT the LLM — scope it tightly
        Sid    = "BedrockEmbeddingsOnly"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ingestion_custom" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = aws_iam_policy.lambda_ingestion_custom.arn
}
