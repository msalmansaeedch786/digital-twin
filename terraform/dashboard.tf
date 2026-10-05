# ===========================================================================
# CloudWatch Ops Dashboard — live health view for the whole stack.
# Free tier: up to 3 dashboards / 50 metrics; this uses ~20.
# Cost data intentionally lives elsewhere (CloudWatch's billing metric tracks
# NET charges, which credits pin to ~$0 — useless here; Cost Explorer covers it).
# ===========================================================================

resource "aws_cloudwatch_dashboard" "ops" {
  dashboard_name = "${var.project_name}-ops"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "## Digital Twin — Live Operations\nAPI traffic, Lambda health, database, and ingestion pipeline. All times UTC. Cost lives in Cost Explorer / the budget alerts (credits make CloudWatch's billing metric read ~$0)."
        }
      },

      # --- Row 1: API Gateway ---
      {
        type = "metric", x = 0, y = 2, width = 8, height = 6
        properties = {
          title  = "API requests (per 5 min)"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.main.id, { stat = "Sum", label = "requests" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 8, y = 2, width = 8, height = 6
        properties = {
          title  = "API errors (per 5 min)"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.main.id, { stat = "Sum", label = "4xx (client/rate-limit)" }],
            ["AWS/ApiGateway", "5xx", "ApiId", aws_apigatewayv2_api.main.id, { stat = "Sum", label = "5xx (server)" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 16, y = 2, width = 8, height = 6
        properties = {
          title  = "API latency"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.main.id, { stat = "p95", label = "p95 ms" }],
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.main.id, { stat = "Average", label = "avg ms" }]
          ]
        }
      },

      # --- Row 2: Lambdas ---
      {
        type = "metric", x = 0, y = 8, width = 8, height = 6
        properties = {
          title  = "Chat Lambda — invocations & errors"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.api.function_name, { stat = "Sum", label = "invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.api.function_name, { stat = "Sum", label = "errors" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 8, y = 8, width = 8, height = 6
        properties = {
          title  = "Chat Lambda — duration"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "p95", label = "p95 ms" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "Average", label = "avg ms" }]
          ]
        }
      },
      {
        type = "metric", x = 16, y = 8, width = 8, height = 6
        properties = {
          title  = "Ingestion Lambda & dead letters"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "Sum", label = "ingestion runs" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "Sum", label = "ingestion errors" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.ingestion_dlq.name, { stat = "Maximum", label = "DLQ depth (must stay 0)" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },

      # --- Row 3: Grounding ---
      # Replaced the RDS CPU / connections / free-storage panels, which died with
      # the database. This is the metric that matters for a RAG system and the one
      # the old panels could never have shown: whether answers are still grounded.
      # Every technical metric can look healthy while the twin confidently invents
      # a career, and that failure is only visible here.
      {
        type = "metric", x = 0, y = 14, width = 24, height = 6
        properties = {
          title  = "Ungrounded answers (must stay 0)"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["DigitalTwin", "UngroundedAnswers", { stat = "Sum", label = "chat answers with 0 retrieved documents" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },

      # --- Row 4: every alarm at a glance ---
      {
        type = "alarm", x = 0, y = 20, width = 24, height = 3
        properties = {
          title = "All guards (grey = OK, red = firing)"
          alarms = [
            aws_cloudwatch_metric_alarm.api_abuse.arn,
            aws_cloudwatch_metric_alarm.ingestion_dlq.arn,
            aws_cloudwatch_metric_alarm.lambda_api_errors.arn,
            aws_cloudwatch_metric_alarm.lambda_api_throttles.arn,
            aws_cloudwatch_metric_alarm.lambda_api_duration_p99.arn,
            # The three RDS alarms went with the database. This one was missing
            # from the panel and is the one that matters most: every other guard
            # here can be green while the twin answers from the model's priors
            # because retrieval returned nothing.
            aws_cloudwatch_metric_alarm.ungrounded_answers.arn
          ]
        }
      }
    ]
  })
}

output "ops_dashboard_url" {
  description = "Live CloudWatch operations dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.ops.dashboard_name}"
}
