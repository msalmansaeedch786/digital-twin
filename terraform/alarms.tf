# ===========================================================================
# CloudWatch Alarms + SNS — Operational Observability
# AWS Well-Architected: Reliability & Operational Excellence pillars
# ===========================================================================

# SNS Topic for all alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = { Name = "${var.project_name}-alerts" }
}

# Subscribe your email to get alert notifications
# After `terraform apply`, confirm the subscription from your inbox
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ===========================================================================
# Cost Guardrail — the /chat endpoint is public and unauthenticated, and every
# request invokes Bedrock. A budget alert is the cheapest defense against
# abuse-driven bill surprises (Lambda account concurrency of 10 and API GW
# throttling are the other layers).
# ===========================================================================

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Track GROSS usage: count what AWS *would* charge, ignoring credits/refunds.
  # Without this the budget measures net (~$0 while credits apply) and stays
  # dormant — this makes it live now so abuse-driven usage is visible even
  # though credits are footing the bill.
  cost_types {
    include_credit             = false
    include_refund             = false
    include_discount           = true
    use_amortized              = false
    include_tax                = true
    include_subscription       = true
    include_upfront            = true
    include_recurring          = true
    include_other_subscription = true
    include_support            = true
    use_blended                = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ===========================================================================
# Real-time abuse alarm — the public /chat endpoint gets hammered
# Fires within ~5 min (CloudWatch metrics, not billing data) if request volume
# spikes far above what a real visitor produces. This is the fast tripwire;
# the budget above is the slow money backstop.
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "api_abuse" {
  alarm_name        = "${var.project_name}-api-abuse"
  alarm_description = "API Gateway request volume spiked — possible abuse of the public /chat endpoint. Check the source IP in the API Gateway access logs."

  namespace   = "AWS/ApiGateway"
  metric_name = "Count"
  dimensions  = { ApiId = aws_apigatewayv2_api.main.id }

  statistic           = "Sum"
  period              = 900 # 15-minute window
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.abuse_request_threshold_15m
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ===========================================================================
# API Lambda Alarms
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_api_errors" {
  alarm_name          = "${var.project_name}-api-errors"
  alarm_description   = "API Lambda error rate is elevated — check logs immediately"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_api_throttles" {
  alarm_name          = "${var.project_name}-api-throttles"
  alarm_description   = "API Lambda is being throttled — reserved concurrency may be too low"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_api_duration_p99" {
  alarm_name          = "${var.project_name}-api-duration-p99"
  alarm_description   = "API Lambda P99 duration > 25 seconds — approaching timeout limit"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 25000 # milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}



# ===========================================================================
# RDS Alarms
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-cpu"
  alarm_description   = "RDS CPU utilization > 80% — check for slow queries or connection storms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-rds-connections"
  alarm_description   = "RDS connection count > 80 — possible connection pool exhaustion"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-rds-storage"
  alarm_description   = "RDS free storage < 5GB — database disk is running low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 5000000000 # 5 GB in bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
