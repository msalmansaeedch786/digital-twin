# ===========================================================================
# Lambda Function — Backend API
# ===========================================================================

locals {
  # The origins allowed to call the API: the Amplify branch domain, the custom
  # domain (salman.is-a.dev) when set, and localhost for dev. Used for both the
  # Lambda ALLOWED_ORIGINS env var and the API Gateway CORS config.
  amplify_origin = "https://${replace(var.git_branch, "/", "-")}.${aws_amplify_app.frontend.default_domain}"
  allowed_origins = concat(
    [local.amplify_origin],
    var.custom_domain == "" ? [] : ["https://${var.custom_domain}"],
    ["http://localhost:3000"],
  )
}

resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/${var.project_name}-api"
  retention_in_days = 30
}

resource "aws_s3_object" "lambda_api_zip" {
  bucket = aws_s3_bucket.deployments.id
  key    = "lambdas/api-${filemd5("${path.module}/../lambdas/api/api_lambda.zip")}.zip"
  source = "${path.module}/../lambdas/api/api_lambda.zip"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api"
  role          = aws_iam_role.lambda_api.arn # Dedicated API role (not shared)
  handler       = "main.handler"              # Mangum wrapper in main.py

  # Deploy via S3 to bypass the 50MB API limit
  s3_bucket        = aws_s3_bucket.deployments.id
  s3_key           = aws_s3_object.lambda_api_zip.key
  source_code_hash = filebase64sha256("${path.module}/../lambdas/api/api_lambda.zip")

  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 30 # 30 seconds for API requests
  memory_size   = 1024

  # AWS X-Ray Active Tracing — full distributed trace visibility
  tracing_config {
    mode = "Active"
  }

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
      ALLOWED_ORIGINS   = join(",", local.allowed_origins)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_api
  ]
}

# ===========================================================================
# API Gateway (HTTP API) — with throttling and scoped CORS
# ===========================================================================

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  # CORS: Locked down to the specific Amplify frontend domain only
  cors_configuration {
    allow_origins     = local.allowed_origins
    allow_methods     = ["POST", "GET", "OPTIONS"]
    allow_headers     = ["content-type"]
    allow_credentials = false # No cookies/sessions — credentials not needed
    max_age           = 300
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # API Gateway access logs
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_access.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }

  # Default throttling — applies to all routes
  default_route_settings {
    throttling_burst_limit   = 50 # Max concurrent requests
    throttling_rate_limit    = 20 # Requests per second steady state
    detailed_metrics_enabled = true
  }
}

# CloudWatch Log Group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_gateway_access" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  integration_method     = "POST"
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

# ===========================================================================
# EventBridge Warm-Up Rule — Keep Lambda warm to avoid cold starts
# Invokes the /warmup endpoint every 5 minutes during business hours
# ===========================================================================

resource "aws_cloudwatch_event_rule" "lambda_warmup" {
  name                = "${var.project_name}-lambda-warmup"
  description         = "Keep the API Lambda warm by invoking it every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "lambda_warmup" {
  rule      = aws_cloudwatch_event_rule.lambda_warmup.name
  target_id = "LambdaWarmup"
  arn       = aws_lambda_function.api.arn

  input = jsonencode({
    source         = "aws.events"
    warmup         = true
    routeKey       = "GET /warmup"
    rawPath        = "/warmup"
    rawQueryString = ""
    headers        = { "content-type" = "application/json" }
    requestContext = {
      http = { method = "GET", path = "/warmup" }
    }
  })
}

resource "aws_lambda_permission" "eventbridge_warmup" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_warmup.arn
}
