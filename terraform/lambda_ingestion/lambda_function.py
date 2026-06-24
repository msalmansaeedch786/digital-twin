import os
import json
import boto3
import urllib.parse
from pathlib import Path

from langchain_community.document_loaders import PyPDFLoader, TextLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_aws import BedrockEmbeddings
from langchain_postgres import PGVector
import psycopg

s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager')

def get_db_connection_string():
    secret_arn = os.environ['DB_SECRET_ARN']
    db_host = os.environ['DB_HOST']
    db_name = os.environ['DB_NAME']
    
    # Retrieve secret
    response = secrets_client.get_secret_value(SecretId=secret_arn)
    secret = json.loads(response['SecretString'])
    
    username = secret['username']
    password = secret['password']
    
    # Construct postgresql URI
    # Format: postgresql+psycopg://user:password@host:port/dbname
    password_encoded = urllib.parse.quote_plus(password)
    return f"postgresql+psycopg://{username}:{password_encoded}@{db_host}:5432/{db_name}"

def init_db(connection_string):
    """Ensure pgvector extension is created."""
    # Strip the +psycopg part for raw psycopg3 connection
    raw_conn_string = connection_string.replace('postgresql+psycopg://', 'postgresql://')
    
    # We must connect, enable autocommit, and create the extension
    with psycopg.connect(raw_conn_string, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")

def lambda_handler(event, context):
    print("Event received:", json.dumps(event))
    
    # 1. Setup Bedrock embeddings
    embeddings = BedrockEmbeddings(
        model_id="amazon.titan-embed-text-v2:0",
        region_name=os.environ['AWS_REGION']
    )
    
    # 2. Setup Vector Store
    conn_string = get_db_connection_string()
    
    # Initialize DB (create extension if needed)
    init_db(conn_string)
    
    vector_store = PGVector(
        embeddings=embeddings,
        collection_name="digital_twin_docs",
        connection=conn_string,
        use_jsonb=True,
    )
    
    # 3. Process records from S3 event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing object: {key} from bucket: {bucket}")
        
        # Download object to /tmp
        tmp_path = f"/tmp/{os.path.basename(key)}"
        s3_client.download_file(bucket, key, tmp_path)
        
        # 4. Load Document
        docs = []
        try:
            if key.lower().endswith('.pdf'):
                loader = PyPDFLoader(tmp_path)
                docs = loader.load()
            elif key.lower().endswith('.txt') or key.lower().endswith('.md'):
                loader = TextLoader(tmp_path)
                docs = loader.load()
            else:
                print(f"Unsupported file type: {key}. Skipping.")
                continue
                
            print(f"Loaded {len(docs)} document chunks from {key}")
            
            # 5. Split Document
            text_splitter = RecursiveCharacterTextSplitter(
                chunk_size=1000,
                chunk_overlap=200,
                length_function=len
            )
            chunks = text_splitter.split_documents(docs)
            print(f"Split into {len(chunks)} text chunks.")
            
            # Add metadata about source
            for chunk in chunks:
                chunk.metadata['source_key'] = key
                chunk.metadata['bucket'] = bucket
            
            # 6. Store in pgvector
            vector_store.add_documents(chunks)
            print(f"Successfully stored {len(chunks)} chunks in pgvector.")
            
        except Exception as e:
            print(f"Error processing {key}: {str(e)}")
            raise e
        finally:
            # Cleanup temp file
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
                
    return {
        'statusCode': 200,
        'body': json.dumps('Ingestion complete')
    }
