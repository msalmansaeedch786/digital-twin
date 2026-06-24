# ===========================================================================
# Lambda Function — Backend API
# ===========================================================================

resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/${var.project_name}-api"
  retention_in_days = 14
}

resource "aws_s3_object" "lambda_api_zip" {
  bucket = aws_s3_bucket.deployments.id
  key    = "lambdas/api-${filemd5("${path.module}/../backend/api_lambda.zip")}.zip"
  source = "${path.module}/../backend/api_lambda.zip"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "main.handler" # Mangum wrapper in main.py
  
  # Deploy via S3 to bypass the 50MB API limit
  s3_bucket        = aws_s3_bucket.deployments.id
  s3_key           = aws_s3_object.lambda_api_zip.key
  source_code_hash = filebase64sha256("${path.module}/../backend/api_lambda.zip")

  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 30 # 30 seconds for API requests
  memory_size   = 1024

  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST           = aws_db_instance.postgres.address
      DB_NAME           = aws_db_instance.postgres.db_name
      DB_SECRET_ARN     = aws_db_instance.postgres.master_user_secret[0].secret_arn
      AWS_EXECUTION_ENV = "AWS_Lambda_python3.12"
      ENVIRONMENT       = "production"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_api
  ]
}

# ===========================================================================
# API Gateway (HTTP API)
# ===========================================================================

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.api.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
