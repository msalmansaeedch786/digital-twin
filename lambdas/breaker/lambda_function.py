"""Circuit breaker for the public /chat API.

Triggered by EventBridge when the api-abuse CloudWatch alarm enters ALARM:
sets the API Gateway stage throttle to 0/0, which makes API Gateway reject
every request with 429 before Lambda or Bedrock ever run — the attack is cut
off at the front door while it is still happening.

Reopening is automatic and self-healing: a second EventBridge rule fires this
same Lambda when the alarm returns to OK, which restores the normal throttle.
This is safe because API Gateway's request Count metric includes the rejected
429s, so the alarm stays in ALARM for as long as the attacker keeps sending —
it only clears once the flood actually stops. So "alarm -> OK" is a reliable
"attack is over" signal, not merely "the door is shut."

Manual reopen is still available if ever needed:
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


def _reopen(reason: str) -> dict:
    _set_throttle(NORMAL_RATE, NORMAL_BURST)
    sns.publish(
        TopicArn=ALERT_TOPIC_ARN,
        Subject="digital-twin: circuit breaker RESET — API reopened",
        Message=(
            f"{reason}\n\n"
            "The API throttle has been restored to "
            f"{NORMAL_RATE:g} req/s (burst {NORMAL_BURST}). "
            "Traffic is flowing normally again."
        ),
    )
    return {"status": "reopened"}


def lambda_handler(event, context):
    # Manual reopen (operator-invoked)
    if event.get("action") == "reopen":
        return _reopen("Circuit breaker was reopened manually.")

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
                "This will reopen automatically once the flood stops and the alarm "
                "returns to OK. No action needed."
            ),
        )
        return {"status": "engaged"}

    # Auto-reopen: the alarm only clears once the attacker actually stops
    # sending (429s are still counted), so OK reliably means the attack is over.
    if state == "OK":
        return _reopen("The abuse alarm cleared (the request flood has stopped).")

    return {"status": "ignored", "reason": f"unhandled event state: {state!r}"}
