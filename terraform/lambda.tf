# ===========================================================================
# Lambda Function — Data Ingestion
# ===========================================================================

resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  name              = "/aws/lambda/${var.project_name}-ingestion"
  retention_in_days = 30
}

# ---------------------------------------------------------------------------
# Deployment S3 Bucket — Hardened to match knowledge base standards
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "deployments" {
  bucket_prefix = "${var.project_name}-deployments-"
  tags          = { Name = "${var.project_name}-deployments" }
}

resource "aws_s3_bucket_versioning" "deployments" {
  bucket = aws_s3_bucket.deployments.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deployments" {
  bucket = aws_s3_bucket.deployments.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "deployments" {
  bucket                  = aws_s3_bucket.deployments.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule to delete old Lambda ZIPs after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "deployments" {
  bucket = aws_s3_bucket.deployments.id

  rule {
    id     = "expire-old-lambda-zips"
    status = "Enabled"

    filter { prefix = "lambdas/" }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ---------------------------------------------------------------------------
# Ingestion Lambda
# ---------------------------------------------------------------------------

resource "aws_s3_object" "lambda_ingestion_zip" {
  bucket = aws_s3_bucket.deployments.id
  key    = "lambdas/ingestion-${filemd5("${path.module}/../lambdas/ingestion/lambda_function.zip")}.zip"
  source = "${path.module}/../lambdas/ingestion/lambda_function.zip"
}

resource "aws_lambda_function" "ingestion" {
  function_name = "${var.project_name}-ingestion"
  role          = aws_iam_role.lambda_ingestion.arn # Dedicated ingestion role
  handler       = "lambda_function.lambda_handler"

  # Deploy via S3 to bypass the 50MB API limit
  s3_bucket        = aws_s3_bucket.deployments.id
  s3_key           = aws_s3_object.lambda_ingestion_zip.key
  source_code_hash = filebase64sha256("${path.module}/../lambdas/ingestion/lambda_function.zip")

  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 300 # 5 minutes for document parsing and embedding
  memory_size   = 1024

  # X-Ray tracing disabled (endpoint removed for cost) — logs + DLQ alarm cover
  # ingestion observability.
  tracing_config {
    mode = "PassThrough"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }



  environment {
    variables = {
      DB_HOST                    = aws_db_instance.postgres.address
      DB_NAME                    = aws_db_instance.postgres.db_name
      DB_SECRET_ARN              = aws_db_instance.postgres.master_user_secret[0].secret_arn
      ENVIRONMENT                = "production"
      BEDROCK_EMBEDDING_MODEL_ID = var.bedrock_embedding_model_id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_ingestion
  ]
}

# ---------------------------------------------------------------------------
# Dead-Letter Queue — async S3-triggered invokes retry twice, then the event
# is LOST unless captured. Failed ingestion events land here (with the full
# payload) so a bad document never silently vanishes from the knowledge base.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "ingestion_dlq" {
  name                      = "${var.project_name}-ingestion-dlq"
  message_retention_seconds = 1209600 # 14 days to notice + replay
  sqs_managed_sse_enabled   = true
  tags                      = { Name = "${var.project_name}-ingestion-dlq" }
}

resource "aws_lambda_function_event_invoke_config" "ingestion" {
  function_name          = aws_lambda_function.ingestion.function_name
  maximum_retry_attempts = 2

  destination_config {
    on_failure {
      destination = aws_sqs_queue.ingestion_dlq.arn
    }
  }
}

# Alert the moment anything lands in the DLQ
resource "aws_cloudwatch_metric_alarm" "ingestion_dlq" {
  alarm_name          = "${var.project_name}-ingestion-dlq-messages"
  alarm_description   = "An ingestion event failed all retries and landed in the DLQ — a document did NOT make it into the knowledge base"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.ingestion_dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ===========================================================================
# S3 Event Trigger for Lambda
# ===========================================================================

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.knowledge_base.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.knowledge_base.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingestion.arn
    # ObjectRemoved:* covers both hard deletes and the DeleteMarkerCreated
    # events this versioned bucket emits on `aws s3 sync --delete`, so the
    # Lambda can purge a deleted file's vectors from pgvector.
    events        = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_suffix = ""
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
