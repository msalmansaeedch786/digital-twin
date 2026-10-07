# ===========================================================================
# CloudWatch Ops Dashboard — live health view for the whole stack.
# Free tier: up to 3 dashboards / 50 metrics; this uses ~20.
# Cost data intentionally lives elsewhere (CloudWatch's billing metric tracks
# NET charges, which credits pin to ~$0 — useless here; Cost Explorer covers it).
# ===========================================================================

resource "aws_cloudwatch_dashboard" "ops" {
  dashboard_name = "${var.project_name}-ops"

  # Redesigned 2026-10-07. The previous version was seven small time-series
  # charts in a grid, which answered "what are all the numbers" rather than the
  # question you actually open a dashboard to ask: is anything wrong right now?
  #
  # Now: four big numbers you can read in a second, the alarm strip, and only the
  # two graphs where the SHAPE matters rather than the value.
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# Digital Twin\nIf all four numbers below are **0** except requests, and the strip is grey, everything is fine. Times are UTC. Cost is not here on purpose \u2014 credits pin CloudWatch's billing metric to ~$0; see the budget alerts and `tutorial.md`."
        }
      },

      # --- Row 1: the four numbers that answer "is it healthy" -------------
      # singleValue over 24h, not a chart. A chart of mostly-zero is harder to
      # read than the number zero.
      {
        type = "metric", x = 0, y = 2, width = 6, height = 5
        properties = {
          title     = "Requests (24h)"
          region    = var.aws_region
          view      = "singleValue"
          period    = 86400
          stat      = "Sum"
          sparkline = true
          metrics   = [["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.main.id]]
        }
      },
      {
        type = "metric", x = 6, y = 2, width = 6, height = 5
        properties = {
          title     = "Errors (24h)"
          region    = var.aws_region
          view      = "singleValue"
          period    = 86400
          stat      = "Sum"
          sparkline = true
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.api.function_name, { label = "chat" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.ingestion.function_name, { label = "ingestion" }]
          ]
        }
      },
      {
        # The one that matters most. Every other number can be healthy while
        # this is non-zero and the twin is inventing a career.
        type = "metric", x = 12, y = 2, width = 6, height = 5
        properties = {
          title     = "Ungrounded answers (24h)"
          region    = var.aws_region
          view      = "singleValue"
          period    = 86400
          stat      = "Sum"
          sparkline = true
          metrics   = [["DigitalTwin", "UngroundedAnswers", { label = "must stay 0" }]]
        }
      },
      {
        type = "metric", x = 18, y = 2, width = 6, height = 5
        properties = {
          title   = "Documents that failed to ingest"
          region  = var.aws_region
          view    = "singleValue"
          period  = 300
          stat    = "Maximum"
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.ingestion_dlq.name, { label = "stuck in DLQ" }]]
        }
      },

      # --- Row 2: every guard at a glance ---------------------------------
      {
        type = "alarm", x = 0, y = 7, width = 24, height = 3
        properties = {
          title = "All guards (grey = OK, red = firing)"
          alarms = [
            aws_cloudwatch_metric_alarm.api_abuse.arn,
            aws_cloudwatch_metric_alarm.ingestion_dlq.arn,
            aws_cloudwatch_metric_alarm.lambda_api_errors.arn,
            aws_cloudwatch_metric_alarm.lambda_api_throttles.arn,
            aws_cloudwatch_metric_alarm.lambda_api_duration_p99.arn,
            aws_cloudwatch_metric_alarm.ungrounded_answers.arn,
            aws_cloudwatch_metric_alarm.root_usage.arn
          ]
        }
      },

      # --- Row 3: the only two graphs where the shape tells you something --
      {
        type = "metric", x = 0, y = 10, width = 12, height = 7
        properties = {
          title  = "Answer latency \u2014 is it getting slower?"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "p95", label = "p95 ms" }],
            ["...", { stat = "Average", label = "average ms" }]
          ]
          yAxis = { left = { min = 0, label = "ms", showUnits = false } }
          annotations = {
            horizontal = [{ label = "baseline 1098 ms", value = 1098 }]
          }
        }
      },
      {
        type = "metric", x = 12, y = 10, width = 12, height = 7
        properties = {
          title  = "Traffic \u2014 is something hammering it?"
          region = var.aws_region, view = "timeSeries", stacked = false, period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.main.id, { stat = "Sum", label = "requests" }],
            ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.main.id, { stat = "Sum", label = "4xx (incl. throttled)" }]
          ]
          yAxis = { left = { min = 0, showUnits = false } }
          annotations = {
            horizontal = [{ label = "abuse alarm at 150/min", value = 150 }]
          }
        }
      }
    ]
  })
}
