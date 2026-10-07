"""Publish AWS cost into CloudWatch so a dashboard can chart it.

CloudWatch has no cost data for this account on its own. AWS/Billing's
EstimatedCharges metric exists only in us-east-1, reports NET charges — which
credits pin to $0 — and this account publishes no AWS/Billing metrics at all.
So the figures have to come from Cost Explorer and be pushed in as custom metrics.

WHY THERE IS NO BACKFILL. The obvious design is to publish the last fortnight of
daily cost on every run, timestamped by the day it belongs to, so the chart is
populated immediately and a missed run heals itself. That does not work. Measured
2026-10-07: CloudWatch accepts backdated PutMetricData without error, registers
the metric in ListMetrics, and then retains nothing — a point one day old is as
unreadable as one twelve days old, while an identical point timestamped `now` is
queryable within ten seconds. Tested across three namespaces with a three-minute
settle. So each run publishes ONE figure stamped `now`, and the chart builds
forward from first deploy rather than arriving complete.

Costs real money: every Cost Explorer request is $0.01, more per month than this
stack costs to run. One request per invocation. The schedule is a Terraform
variable for that reason — see terraform/cost_dashboard.tf.
"""

import datetime
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

NAMESPACE = os.environ.get("METRIC_NAMESPACE", "DigitalTwin/Cost")
# Services under this are rolled into "Other"; a stacked chart with twenty
# near-zero bands is unreadable.
MIN_SERVICE_USD = float(os.environ.get("MIN_SERVICE_USD", "0.005"))

ce = boto3.client("ce", region_name="us-east-1")
cw = boto3.client("cloudwatch")


def lambda_handler(event, context):
    today = datetime.datetime.now(datetime.timezone.utc).date()
    # Cost Explorer lags roughly a day, so "yesterday" is the newest complete
    # figure. End is exclusive.
    start, end = today - datetime.timedelta(days=2), today

    # RECORD_TYPE=Usage is the whole point: without it credits net the total to
    # zero and the dashboard reads $0 while real money is being spent.
    response = ce.get_cost_and_usage(
        TimePeriod={"Start": start.isoformat(), "End": end.isoformat()},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        Filter={"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Usage"]}},
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    periods = response.get("ResultsByTime", [])
    if not periods:
        logger.warning("Cost Explorer returned no periods")
        return {"published": 0}

    # Newest complete day.
    period = periods[-1]
    day = period["TimePeriod"]["Start"]
    stamp = datetime.datetime.now(datetime.timezone.utc)

    total, other = 0.0, 0.0
    data = []
    for group in period.get("Groups", []):
        amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
        total += amount
        if amount < MIN_SERVICE_USD:
            other += amount
            continue
        data.append({
            "MetricName": "DailyCost",
            "Dimensions": [{"Name": "Service", "Value": group["Keys"][0][:255]}],
            "Timestamp": stamp, "Value": round(amount, 6), "Unit": "None",
        })

    if other > 0:
        data.append({"MetricName": "DailyCost",
                     "Dimensions": [{"Name": "Service", "Value": "Other"}],
                     "Timestamp": stamp, "Value": round(other, 6), "Unit": "None"})

    data.append({"MetricName": "DailyCostTotal",
                 "Timestamp": stamp, "Value": round(total, 6), "Unit": "None"})
    # Projection is the headline most people actually want, and computing it here
    # keeps the dashboard free of metric maths that hides the assumption.
    data.append({"MetricName": "ProjectedMonthlyCost",
                 "Timestamp": stamp, "Value": round(total * 30, 4), "Unit": "None"})

    cw.put_metric_data(Namespace=NAMESPACE, MetricData=data)

    logger.info("published cost metrics", extra={
        "cost_day": day, "total_usd": round(total, 4),
        "projected_monthly_usd": round(total * 30, 2), "series": len(data),
    })
    return {"cost_day": day, "total": round(total, 6), "series": len(data)}
