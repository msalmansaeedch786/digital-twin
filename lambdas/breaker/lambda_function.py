"""Circuit breaker for the public /chat API.

Triggered by EventBridge when the api-abuse CloudWatch alarm enters ALARM:
sets the API Gateway stage throttle to 0/0, which makes API Gateway reject
every request with 429 before Lambda or Bedrock ever run — the attack is cut
off at the front door while it is still happening.

Reopening is deliberate, not automatic:
  aws lambda invoke --function-name digital-twin-breaker \
      --payload '{"action": "reopen"}' --cli-binary-format raw-in-base64-out out.json
(Any terraform apply also restores the normal throttle, since the stage's
default_route_settings are declared in code.)
"""

import json
import os

import boto3

apigw = boto3.client("apigatewayv2")
sns = boto3.client("sns")

API_ID = os.environ["API_ID"]
STAGE_NAME = os.environ.get("STAGE_NAME", "$default")
NORMAL_RATE = float(os.environ.get("NORMAL_RATE", "5"))
NORMAL_BURST = int(os.environ.get("NORMAL_BURST", "10"))
ALERT_TOPIC_ARN = os.environ["ALERT_TOPIC_ARN"]


def _set_throttle(rate: float, burst: int) -> None:
    apigw.update_stage(
        ApiId=API_ID,
        StageName=STAGE_NAME,
        DefaultRouteSettings={
            "ThrottlingRateLimit": rate,
            "ThrottlingBurstLimit": burst,
        },
    )


def lambda_handler(event, context):
    if event.get("action") == "reopen":
        _set_throttle(NORMAL_RATE, NORMAL_BURST)
        sns.publish(
            TopicArn=ALERT_TOPIC_ARN,
            Subject="digital-twin: circuit breaker RESET — API reopened",
            Message=(
                "The API throttle has been restored to "
                f"{NORMAL_RATE:g} req/s (burst {NORMAL_BURST}). "
                "Traffic is flowing normally again."
            ),
        )
        return {"status": "reopened"}

    state = event.get("detail", {}).get("state", {}).get("value")
    if state == "ALARM":
        _set_throttle(0, 0)
        sns.publish(
            TopicArn=ALERT_TOPIC_ARN,
            Subject="digital-twin: CIRCUIT BREAKER ENGAGED — API closed",
            Message=(
                "The abuse alarm fired (request flood on /chat) and the circuit "
                "breaker set the API throttle to 0 — every request now gets a 429 "
                "at the front door and costs you nothing.\n\n"
                "When you are ready to reopen:\n"
                '  aws lambda invoke --function-name digital-twin-breaker '
                '--payload \'{"action": "reopen"}\' '
                "--cli-binary-format raw-in-base64-out /tmp/out.json\n\n"
                "(A terraform apply also reopens it.)"
            ),
        )
        return {"status": "engaged"}

    return {"status": "ignored", "reason": f"unhandled event state: {state!r}"}
