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

      # --- Row 3: Database ---
      {
        type = "metric", x = 0, y = 14, width = 8, height = 6
        properties = {
          title  = "RDS CPU %"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { stat = "Average", label = "cpu %" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 8, y = 14, width = 8, height = 6
        properties = {
          title  = "RDS connections"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { stat = "Maximum", label = "connections" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 16, y = 14, width = 8, height = 6
        properties = {
          title  = "RDS free storage (GB)"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { stat = "Minimum", label = "free bytes" }]
          ]
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
            aws_cloudwatch_metric_alarm.rds_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_connections.arn,
            aws_cloudwatch_metric_alarm.rds_storage.arn
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
