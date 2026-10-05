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

resource "aws_iam_policy" "lambda_api_custom" {
  name        = "${var.project_name}-lambda-api-policy"
  description = "Least-privilege policy for the API Lambda: Bedrock + S3 Vectors (read only)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        # Model ids come from variables.tf so the env vars and this policy can
        # never drift apart. The inference profile keeps its geo prefix ("eu.");
        # the underlying foundation-model ARN drops it.
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_embedding_model_id}",
          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_llm_model_id}",
          "arn:aws:bedrock:*::foundation-model/${trimprefix(var.bedrock_llm_model_id, "eu.")}"
        ]
      },
      {
        # Retrieval only. The Lambda cannot write, delete or enumerate, so a
        # compromised API Lambda still cannot corrupt the index or dump it
        # wholesale.
        #
        # GetVectors is NOT redundant: a single QueryVectors call with
        # returnMetadata=true authorises BOTH actions, because returning the
        # chunk text is a read of the vector. Granting QueryVectors alone looks
        # correct and fails at runtime with
        #   "not authorized to perform: s3vectors:GetVectors"
        # which is how it reached production. AWS's action reference lists the
        # two separately and does not say one implies the other, and an
        # admin-credentialed test cannot reveal it.
        Sid    = "S3VectorsQueryAccess"
        Effect = "Allow"
        Action = [
          "s3vectors:QueryVectors",
          "s3vectors:GetVectors"
        ]
        Resource = [aws_s3vectors_index.documents.index_arn]
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
        # Ingestion only needs embeddings, NOT the LLM — scope it tightly
        Sid    = "BedrockEmbeddingsOnly"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_embedding_model_id}"
        ]
      },
      {
        # Writes chunks, and removes a file's old chunks when it is re-uploaded
        # or deleted. ListVectors is required because S3 Vectors can only delete
        # by vector key — there is no delete-by-metadata-filter — so finding a
        # source file's chunks means scanning the index and matching the
        # "<source_key>#<n>" prefix. See lambdas/shared/s3_vector_store.py.
        Sid    = "S3VectorsWriteAccess"
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:ListVectors",
          "s3vectors:DeleteVectors"
        ]
        Resource = [aws_s3vectors_index.documents.index_arn]
      },
      {
        # Lambda delivers failed async events to the DLQ using THIS role
        Sid      = "DlqSendMessage"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.ingestion_dlq.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ingestion_custom" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = aws_iam_policy.lambda_ingestion_custom.arn
}
