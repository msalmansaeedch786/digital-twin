# ===========================================================================
# Lambda Function — Data Ingestion
# ===========================================================================

resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  name              = "/aws/lambda/${var.project_name}-ingestion"
  retention_in_days = 14
}

resource "aws_s3_bucket" "deployments" {
  bucket_prefix = "${var.project_name}-deployments-"
}

resource "aws_s3_object" "lambda_ingestion_zip" {
  bucket = aws_s3_bucket.deployments.id
  key    = "lambdas/ingestion-${filemd5("${path.module}/lambda_ingestion/lambda_function.zip")}.zip"
  source = "${path.module}/lambda_ingestion/lambda_function.zip"
}

resource "aws_lambda_function" "ingestion" {
  function_name = "${var.project_name}-ingestion"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  
  # Deploy via S3 to bypass the 50MB API limit
  s3_bucket        = aws_s3_bucket.deployments.id
  s3_key           = aws_s3_object.lambda_ingestion_zip.key
  source_code_hash = filebase64sha256("${path.module}/lambda_ingestion/lambda_function.zip")

  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 300 # 5 minutes for document parsing and embedding
  memory_size   = 1024

  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST       = aws_db_instance.postgres.address
      DB_NAME       = aws_db_instance.postgres.db_name
      DB_SECRET_ARN = aws_db_instance.postgres.master_user_secret[0].secret_arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_ingestion
  ]
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
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
