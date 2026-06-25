from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import RDS
from diagrams.aws.network import APIGateway, VPC, PrivateSubnet, Endpoint
from diagrams.aws.security import SecretsManager
from diagrams.aws.ml import Bedrock
from diagrams.aws.storage import S3
from diagrams.aws.management import Cloudwatch
from diagrams.aws.integration import Eventbridge, SNS
from diagrams.onprem.client import User
from diagrams.programming.framework import React

with Diagram("Digital Twin Architecture (Enterprise Secure)", show=False, filename="frontend/public/architecture", outformat="png", direction="TB"):
    user = User("End User")
    browser = React("Browser (Next.js)")

    with Cluster("AWS Cloud - eu-central-1"):
        apigw = APIGateway("API Gateway")
        eventbridge = Eventbridge("EventBridge\n(Warm-Up)")
        
        with Cluster("Amazon VPC (10.0.0.0/16)"):
            with Cluster("Private Subnets"):
                lambda_api = Lambda("API Backend\n(FastAPI)")
                lambda_ingest = Lambda("Ingestion Pipeline")
                rds = RDS("PostgreSQL 16\n+ pgvector")
                
                # VPC Endpoints
                vpce_bedrock = Endpoint("Bedrock Endpoint")
                vpce_secrets = Endpoint("Secrets Endpoint")
                vpce_cw = Endpoint("Logs Endpoint")

        with Cluster("AI & Machine Learning"):
            bedrock_llm = Bedrock("Nova Lite\nLLM")
            bedrock_emb = Bedrock("Titan\nEmbeddings V2")

        with Cluster("Storage & Knowledge Base"):
            s3_kb = S3("Knowledge Base\nDocuments")
            vpce_s3 = Endpoint("S3 Gateway Endpoint")

        with Cluster("Security & Observability"):
            secrets = SecretsManager("RDS Credentials")
            cw = Cloudwatch("Logs & Alarms")
            sns = SNS("Alerts")
            cw >> sns

    # User flows
    user >> browser
    browser >> Edge(label="HTTPS POST /chat") >> apigw
    apigw >> Edge(label="AWS Proxy") >> lambda_api
    
    # API Backend flows (Internal VPC)
    lambda_api >> Edge(label="Port 5432 (Internal)") >> rds
    
    # API Backend flows (VPC Endpoints)
    lambda_api >> vpce_bedrock >> bedrock_llm
    lambda_api >> vpce_bedrock >> bedrock_emb
    lambda_api >> vpce_secrets >> secrets
    lambda_api >> vpce_cw >> cw
    
    # Ingestion flows
    s3_kb >> Edge(label="S3 Event") >> lambda_ingest
    lambda_ingest >> vpce_s3 >> s3_kb
    lambda_ingest >> vpce_bedrock >> bedrock_emb
    lambda_ingest >> Edge(label="Port 5432 (Internal)") >> rds
    
    # EventBridge
    eventbridge >> Edge(label="rate(5 min)") >> lambda_api
