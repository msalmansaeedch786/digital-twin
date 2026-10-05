"""Render the architecture diagram to frontend/public/architecture.png.

Diagram-as-code: this script is the single source of truth for the PNG shown in
the README. When the Terraform changes, update this file and re-run it so the
published diagram never drifts from the deployed infrastructure.

    pip install diagrams        # also needs graphviz  (brew install graphviz)
    python scripts/generate_diagram.py
"""

import os

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.cost import Budgets, CostExplorer
from diagrams.aws.integration import Eventbridge, SNS, SQS
from diagrams.aws.management import Cloudtrail, Cloudwatch, CloudwatchAlarm
from diagrams.aws.ml import Bedrock
from diagrams.aws.mobile import Amplify
from diagrams.aws.network import APIGateway
from diagrams.aws.storage import S3
from diagrams.onprem.client import User
from diagrams.onprem.vcs import Github

graph_attr = {
    "fontsize": "16",
    "bgcolor": "white",
    "splines": "spline",
    "nodesep": "0.6",
    "ranksep": "1.0",
}

# Output relative to the repo root (scripts/ -> repo root) so it renders
# to frontend/public/ no matter which directory the script is run from.
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

with Diagram(
    "Digital Twin — Serverless RAG on AWS (eu-central-1)",
    show=False,
    filename=os.path.join(_ROOT, "frontend/public/architecture"),
    outformat="png",
    direction="TB",
    graph_attr=graph_attr,
):
    user = User("End User")
    domain = Github("GitHub\n(push to main)")

    with Cluster("AWS Cloud — eu-central-1"):
        # --- Edge / entry layer ---
        amplify = Amplify("Amplify Hosting\nNext.js SSR\nmsalmansaeedch.de + www")
        apigw = APIGateway("API Gateway (HTTP)\nthrottle 5 rps / burst 10\nCORS locked to origins")
        warmup = Eventbridge("EventBridge\nrate(5 min) /warmup")

        # --- Compute. No VPC: every dependency is an IAM-authorised HTTPS API, so
        # there is nothing to isolate at the network layer and no endpoints to bill.
        with Cluster("Lambda (arm64, no VPC)"):
            lambda_api = Lambda("API Backend\nFastAPI + Mangum\nLangChain RAG")
            lambda_ingest = Lambda("Ingestion\nchunk + embed")

        # --- AWS-managed services reached via the endpoints ---
        with Cluster("Amazon Bedrock"):
            bedrock_llm = Bedrock("Nova Lite\n(generation)")
            bedrock_emb = Bedrock("Titan Embeddings V2\n(vectors)")

        with Cluster("Storage"):
            s3_vectors = S3("S3 Vectors\ndigital-twin-docs\n1024-dim, cosine")
            s3_kb = S3("Knowledge Base\n(versioned)")
            s3_deploy = S3("Lambda\nDeployment Artifacts")
            dlq = SQS("Ingestion DLQ\n(failed events)")

        # --- Automated abuse defence: alarm -> breaker -> throttle 0/0 ---
        with Cluster("Circuit Breaker (automatic abuse defence)"):
            abuse_alarm = CloudwatchAlarm("api-abuse alarm\n60s period")
            breaker_rules = Eventbridge("Alarm State Change\nALARM  |  OK")
            breaker = Lambda("Breaker Lambda\nclose 0/0 / reopen 5/10")

        with Cluster("Security & Observability"):
            cw = Cloudwatch("Logs, Metrics,\nDashboard, 7 Alarms")
            trail = Cloudtrail("CloudTrail\n(log-file validation)")
            sns = SNS("SNS — Email Alerts")

        with Cluster("Cost Guardrails"):
            budgets = Budgets("Budgets\ndaily $2 / monthly $45")
            anomaly = CostExplorer("Cost Anomaly\nDetection")

    # =====================================================================
    # Request path (synchronous)
    # =====================================================================
    user >> Edge(label="HTTPS (ACM cert)") >> amplify
    amplify >> Edge(label="POST /chat") >> apigw
    apigw >> Edge(label="AWS_PROXY") >> lambda_api
    warmup >> Edge(label="keeps container warm", style="dashed") >> lambda_api

    lambda_api >> Edge(label="QueryVectors (k=5)") >> s3_vectors
    lambda_api >> bedrock_emb
    lambda_api >> bedrock_llm

    # =====================================================================
    # Ingestion path (event-driven)
    # =====================================================================
    s3_kb >> Edge(label="ObjectCreated / ObjectRemoved", style="dashed") >> lambda_ingest
    lambda_ingest >> Edge(label="PutVectors / DeleteVectors") >> s3_vectors
    lambda_ingest >> bedrock_emb
    lambda_ingest >> Edge(label="on failure", style="dashed", color="firebrick") >> dlq

    # =====================================================================
    # Circuit breaker loop: detect -> act -> notify -> self-heal
    # =====================================================================
    apigw >> Edge(label="request count", style="dotted") >> abuse_alarm
    abuse_alarm >> Edge(label="state change") >> breaker_rules
    breaker_rules >> breaker
    breaker >> Edge(label="set stage throttle", color="firebrick") >> apigw
    breaker >> Edge(style="dashed") >> sns

    # =====================================================================
    # Observability + cost wiring
    # =====================================================================
    cw >> Edge(label="alarm") >> sns
    trail >> Edge(style="dashed") >> cw
    budgets >> Edge(style="dashed") >> sns
    anomaly >> Edge(style="dashed") >> sns

    # =====================================================================
    # CI/CD — OIDC, no static credentials
    # =====================================================================
    domain >> Edge(label="OIDC assume-role\nterraform apply", style="dashed") >> s3_deploy
    s3_deploy >> Edge(style="dashed") >> lambda_api
    s3_deploy >> Edge(style="dashed") >> lambda_ingest
