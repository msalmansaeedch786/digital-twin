from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import RDS
from diagrams.aws.network import APIGateway, InternetGateway, VPC, PublicSubnet
from diagrams.aws.security import SecretsManager
from diagrams.aws.ml import Bedrock
from diagrams.aws.storage import S3
from diagrams.aws.management import Cloudwatch, Cloudtrail
from diagrams.aws.integration import Eventbridge, SNS
from diagrams.onprem.client import User
from diagrams.programming.framework import React

with Diagram("Digital Twin Architecture", show=False, filename="frontend/public/architecture", outformat="png", direction="TB"):
    user = User("End User")
    browser = React("Browser (Next.js)")

    with Cluster("AWS Cloud - eu-central-1"):
        apigw = APIGateway("API Gateway")
        eventbridge = Eventbridge("EventBridge\n(Warm-Up Scheduler)")
        
        with Cluster("Serverless Compute (Public Network)"):
            lambda_api = Lambda("API Backend\n(FastAPI)")
            lambda_ingest = Lambda("Ingestion Pipeline")

        with Cluster("AI & Machine Learning"):
            bedrock_llm = Bedrock("Nova Lite\nLLM")
            bedrock_emb = Bedrock("Titan\nEmbeddings V2")

        with Cluster("Amazon VPC"):
            igw = InternetGateway("Internet Gateway")
            with Cluster("Public Subnets"):
                rds = RDS("PostgreSQL 16\n+ pgvector")
                igw >> Edge(color="transparent") >> rds

        with Cluster("Storage & Knowledge Base"):
            s3_kb = S3("Knowledge Base\nDocuments")
            s3_deploy = S3("Deployment\nArtifacts")

        with Cluster("Security & Observability"):
            secrets = SecretsManager("RDS Credentials")
            cw = Cloudwatch("Logs & Alarms")
            sns = SNS("Alerts")
            cw >> sns

    # User flows
    user >> browser
    browser >> Edge(label="HTTPS POST /chat") >> apigw
    apigw >> Edge(label="AWS Proxy") >> lambda_api
    
    # API Backend flows
    lambda_api >> Edge(label="Port 5432 (Public IP)") >> rds
    lambda_api >> Edge(label="Public AWS API") >> bedrock_llm
    lambda_api >> Edge(label="Public AWS API") >> bedrock_emb
    lambda_api >> Edge(label="Public AWS API") >> secrets
    lambda_api >> Edge(label="Public AWS API") >> cw
    
    # Ingestion flows
    s3_kb >> Edge(label="S3 Event Notification") >> lambda_ingest
    lambda_ingest >> Edge(label="Fetch Document") >> s3_kb
    lambda_ingest >> Edge(label="Embed") >> bedrock_emb
    lambda_ingest >> Edge(label="Store Vector") >> rds
    
    # EventBridge
    eventbridge >> Edge(label="rate(5 min)") >> lambda_api
