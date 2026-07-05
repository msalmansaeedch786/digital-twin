import os

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import RDS
from diagrams.aws.network import APIGateway, Endpoint
from diagrams.aws.security import SecretsManager
from diagrams.aws.ml import Bedrock
from diagrams.aws.storage import S3
from diagrams.aws.management import Cloudwatch, Cloudtrail
from diagrams.aws.devtools import XRay
from diagrams.aws.integration import Eventbridge, SNS
from diagrams.aws.mobile import Amplify
from diagrams.onprem.client import User

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
    "Digital Twin Architecture (Enterprise Secure)",
    show=False,
    filename=os.path.join(_ROOT, "frontend/public/architecture"),
    outformat="png",
    direction="TB",
    graph_attr=graph_attr,
):
    user = User("End User")

    with Cluster("AWS Cloud — eu-central-1"):
        # --- Edge / entry layer ---
        amplify = Amplify("AWS Amplify\n(Next.js SSR Hosting)")
        apigw = APIGateway("API Gateway\n(HTTP API + Throttling)")
        eventbridge = Eventbridge("EventBridge\n(Warm-Up)")

        # --- The network boundary ---
        with Cluster("Amazon VPC (10.0.0.0/16)"):
            with Cluster("Private Subnets (2 AZs — no internet route)"):
                lambda_api = Lambda("API Backend\n(FastAPI)")
                lambda_ingest = Lambda("Ingestion Pipeline")
                rds = RDS("PostgreSQL 16\n+ pgvector")

            # VPC Endpoints live INSIDE the VPC (PrivateLink into AWS services)
            with Cluster("VPC Endpoints (PrivateLink)"):
                vpce_bedrock = Endpoint("Bedrock")
                vpce_secrets = Endpoint("Secrets Manager")
                vpce_logs = Endpoint("CloudWatch Logs")
                vpce_xray = Endpoint("X-Ray")
                vpce_s3 = Endpoint("S3 (Gateway)")

        # --- AWS-managed services, reached OUT of the VPC via the endpoints ---
        with Cluster("Amazon Bedrock"):
            bedrock_llm = Bedrock("Nova Lite\n(LLM)")
            bedrock_emb = Bedrock("Titan\nEmbeddings V2")

        with Cluster("Storage & Knowledge Base"):
            s3_kb = S3("Knowledge Base\nDocuments")

        with Cluster("Security & Observability"):
            secrets = SecretsManager("RDS Credentials\n(auto-managed)")
            cw = Cloudwatch("Logs & Alarms")
            xray = XRay("Distributed Tracing")
            trail = Cloudtrail("Audit Logging\n(log-file validation)")
            sns = SNS("Email Alerts")

    # =====================================================================
    # Request path (synchronous)
    # =====================================================================
    user >> Edge(label="HTTPS") >> amplify
    amplify >> Edge(label="POST /chat") >> apigw
    apigw >> Edge(label="AWS_PROXY") >> lambda_api
    eventbridge >> Edge(label="rate(5 min) GET /warmup") >> lambda_api

    # API Lambda → data + services
    lambda_api >> Edge(label="5432") >> rds
    lambda_api >> vpce_bedrock
    lambda_api >> vpce_secrets
    lambda_api >> vpce_logs
    lambda_api >> vpce_xray

    # =====================================================================
    # Ingestion path (event-driven / asynchronous)
    # =====================================================================
    s3_kb >> Edge(label="ObjectCreated", style="dashed") >> lambda_ingest
    lambda_ingest >> Edge(label="5432") >> rds
    lambda_ingest >> vpce_s3
    lambda_ingest >> vpce_bedrock
    lambda_ingest >> vpce_secrets
    lambda_ingest >> vpce_logs
    lambda_ingest >> vpce_xray

    # =====================================================================
    # Endpoints → managed services (traffic leaves via PrivateLink, not the internet)
    # =====================================================================
    vpce_bedrock >> bedrock_llm
    vpce_bedrock >> bedrock_emb
    vpce_secrets >> secrets
    vpce_logs >> cw
    vpce_xray >> xray
    vpce_s3 >> s3_kb

    # =====================================================================
    # Observability wiring
    # =====================================================================
    cw >> Edge(label="alarm") >> sns
    trail >> Edge(label="streams", style="dashed") >> cw
