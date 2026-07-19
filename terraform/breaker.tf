# ===========================================================================
# Circuit Breaker — automatic response to the api-abuse alarm.
# Alarm (1-min periods) -> EventBridge alarm-state-change -> this Lambda ->
# stage throttle 0/0 (every request 429s at the front door) + email.
# Worst-case time from attack start to closed door: ~3-4 minutes.
# Reopen: invoke with {"action":"reopen"} — or any terraform apply, which
# restores the stage's declared default_route_settings.
# ===========================================================================

data "archive_file" "breaker" {
  type        = "zip"
  source_file = "${path.module}/../lambdas/breaker/lambda_function.py"
  output_path = "${path.module}/../lambdas/breaker/breaker.zip"
}

resource "aws_cloudwatch_log_group" "breaker" {
  name              = "/aws/lambda/${var.project_name}-breaker"
  retention_in_days = 30
}

resource "aws_iam_role" "breaker" {
  name               = "${var.project_name}-breaker-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "breaker_basic" {
  role       = aws_iam_role.breaker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "breaker" {
  name        = "${var.project_name}-breaker-policy"
  description = "Circuit breaker: adjust the API stage throttle and notify via SNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UpdateStageThrottle"
        Effect   = "Allow"
        Action   = ["apigateway:PATCH", "apigateway:GET"]
        Resource = ["arn:aws:apigateway:${var.aws_region}::/apis/${aws_apigatewayv2_api.main.id}/stages/*"]
      },
      {
        Sid      = "NotifyAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.alerts.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "breaker_custom" {
  role       = aws_iam_role.breaker.name
  policy_arn = aws_iam_policy.breaker.arn
}

resource "aws_lambda_function" "breaker" {
  function_name    = "${var.project_name}-breaker"
  role             = aws_iam_role.breaker.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.breaker.output_path
  source_code_hash = data.archive_file.breaker.output_base64sha256

  # Deliberately NOT in the VPC: it must reach the API Gateway control plane
  # even if the VPC networking itself is what is on fire.
  environment {
    variables = {
      API_ID          = aws_apigatewayv2_api.main.id
      STAGE_NAME      = "$default"
      NORMAL_RATE     = "5"
      NORMAL_BURST    = "10"
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.breaker]
}

# Fire the breaker the moment the abuse alarm enters ALARM state
resource "aws_cloudwatch_event_rule" "breaker" {
  name        = "${var.project_name}-breaker-on-abuse"
  description = "Trigger the circuit breaker when the api-abuse alarm fires"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    resources   = [aws_cloudwatch_metric_alarm.api_abuse.arn]
    detail      = { state = { value = ["ALARM"] } }
  })
}

resource "aws_cloudwatch_event_target" "breaker" {
  rule      = aws_cloudwatch_event_rule.breaker.name
  target_id = "CircuitBreaker"
  arn       = aws_lambda_function.breaker.arn
}

resource "aws_lambda_permission" "breaker_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.breaker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.breaker.arn
}
