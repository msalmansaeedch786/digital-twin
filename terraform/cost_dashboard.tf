# ===========================================================================
# Cost in CloudWatch
# ===========================================================================
# CloudWatch cannot chart this account's spend on its own. AWS/Billing's
# EstimatedCharges metric exists only in us-east-1, reports NET charges — which
# credits pin to $0 — and this account publishes no AWS/Billing metrics at all
# (verified: list-metrics returns an empty set). So cost has to be fetched from
# Cost Explorer and pushed in as a custom metric.
#
# This costs real money to run, and more than it watches: every Cost Explorer
# request is $0.01, so a daily schedule is ~$0.30/month against infrastructure
# that idles at ~$0.02/month. That is the trade for having spend on a dashboard
# next to the operational metrics instead of in the billing console.
#
# cost_metrics_schedule is a variable so the frequency is a one-line change. Each
# run fetches 14 days and republishes all of them, so a weekly schedule still
# draws a daily chart — it just refreshes weekly, and a missed run backfills.

data "archive_file" "cost_metrics" {
  type        = "zip"
  source_file = "${path.module}/../lambdas/cost_metrics/lambda_function.py"
  output_path = "${path.module}/../lambdas/cost_metrics/cost_metrics.zip"
}

resource "aws_iam_role" "cost_metrics" {
  name               = "${var.project_name}-cost-metrics-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cost_metrics_basic" {
  role       = aws_iam_role.cost_metrics.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "cost_metrics" {
  name        = "${var.project_name}-cost-metrics-policy"
  description = "Read Cost Explorer, write one CloudWatch namespace. Nothing else."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Cost Explorer has no resource-level permissions — ce:GetCostAndUsage
        # can only be granted on "*". Read-only, and the only ce action granted.
        Sid      = "ReadCostExplorer"
        Effect   = "Allow"
        Action   = ["ce:GetCostAndUsage"]
        Resource = "*"
      },
      {
        # PutMetricData likewise cannot be ARN-scoped, so it is constrained by
        # namespace condition instead — this role cannot write metrics that would
        # overwrite the operational ones.
        Sid      = "PublishCostMetricsOnly"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "DigitalTwin/Cost" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cost_metrics" {
  role       = aws_iam_role.cost_metrics.name
  policy_arn = aws_iam_policy.cost_metrics.arn
}

resource "aws_cloudwatch_log_group" "cost_metrics" {
  name              = "/aws/lambda/${var.project_name}-cost-metrics"
  retention_in_days = 30
}

resource "aws_lambda_function" "cost_metrics" {
  function_name = "${var.project_name}-cost-metrics"
  role          = aws_iam_role.cost_metrics.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.cost_metrics.output_path
  source_code_hash = data.archive_file.cost_metrics.output_base64sha256

  environment {
    variables = {
      METRIC_NAMESPACE = "DigitalTwin/Cost"
      DAYS_BACK        = "14"
    }
  }

  depends_on = [aws_cloudwatch_log_group.cost_metrics]
}

resource "aws_cloudwatch_event_rule" "cost_metrics" {
  name                = "${var.project_name}-cost-metrics"
  description         = "Pull Cost Explorer into CloudWatch. Each run costs $0.01."
  schedule_expression = var.cost_metrics_schedule
}

resource "aws_cloudwatch_event_target" "cost_metrics" {
  rule      = aws_cloudwatch_event_rule.cost_metrics.name
  target_id = "cost-metrics-lambda"
  arn       = aws_lambda_function.cost_metrics.arn
}

resource "aws_lambda_permission" "cost_metrics" {
  statement_id  = "AllowScheduledCostMetrics"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_metrics.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_metrics.arn
}

# ---------------------------------------------------------------------------
# The dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "cost" {
  dashboard_name = "${var.project_name}-cost"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# Cost\nGROSS usage from Cost Explorer, so credits do not hide it. Published by `${var.project_name}-cost-metrics` on `${var.cost_metrics_schedule}`; Cost Explorer lags about a day, so the newest bar is usually incomplete. Budgets alert at $0.50/day and $5/month."
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 6, height = 6
        properties = {
          title     = "Yesterday"
          region    = var.aws_region
          view      = "singleValue"
          period    = 86400
          stat      = "Maximum"
          sparkline = true
          metrics   = [["DigitalTwin/Cost", "DailyCostTotal", { label = "USD/day" }]]
        }
      },
      {
        # Yesterday x 30, computed in the Lambda rather than with metric maths so
        # the assumption lives in one readable place instead of inside a widget.
        type = "metric", x = 6, y = 2, width = 6, height = 6
        properties = {
          title     = "At that rate, per month"
          region    = var.aws_region
          view      = "singleValue"
          period    = 86400
          stat      = "Maximum"
          sparkline = true
          metrics   = [["DigitalTwin/Cost", "ProjectedMonthlyCost", { label = "USD/month" }]]
        }
      },
      {
        type = "metric", x = 12, y = 2, width = 12, height = 6
        properties = {
          title   = "Daily cost (gross USD)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 86400
          stat    = "Maximum"
          metrics = [["DigitalTwin/Cost", "DailyCostTotal", { label = "total/day", color = "#1f77b4" }]]
          yAxis   = { left = { min = 0, showUnits = false, label = "USD" } }
          annotations = {
            horizontal = [
              { label = "daily budget $0.50", value = 0.50, color = "#d62728" },
              { label = "before teardown ~$1.14", value = 1.14, color = "#aaaaaa" }
            ]
          }
        }
      },
      {
        type = "metric", x = 0, y = 8, width = 24, height = 7
        properties = {
          title   = "By service (stacked)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = true
          period  = 86400
          stat    = "Maximum"
          # Search expression rather than a fixed list: services appear and
          # disappear from a bill, and a hardcoded list silently drops whatever
          # starts costing money next.
          metrics = [[{ expression = "SEARCH('{DigitalTwin/Cost,Service} MetricName=\"DailyCost\"', 'Maximum', 86400)", id = "svc" }]]
          yAxis   = { left = { min = 0, showUnits = false, label = "USD" } }
        }
      },
      {
        type = "metric", x = 0, y = 15, width = 24, height = 6
        properties = {
          title   = "Is the publisher itself healthy?"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 86400
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.cost_metrics.function_name, { stat = "Sum", label = "runs" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.cost_metrics.function_name, { stat = "Sum", label = "errors" }]
          ]
          yAxis = { left = { min = 0, showUnits = false } }
        }
      }
    ]
  })
}

output "cost_dashboard_url" {
  description = "CloudWatch cost dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.cost.dashboard_name}"
}
