import os
import time
import logging
from pathlib import Path
from dotenv import load_dotenv

from langchain_community.document_loaders import PyPDFLoader, TextLoader, DirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_aws import BedrockEmbeddings
from langchain_postgres import PGVector
import psycopg

# Load environment variables
load_dotenv()

# Setup logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

DATA_DIR = str(Path(__file__).parent.parent / "data")

def get_db_connection_string() -> str:
    """Gets local or remote PostgreSQL connection string."""
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        raise ValueError("DATABASE_URL must be set in .env for local ingestion")
    return db_url

def init_db(connection_string: str):
    """Ensure pgvector extension exists."""
    raw_conn_string = connection_string.replace("postgresql+psycopg://", "postgresql://")
    with psycopg.connect(raw_conn_string, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    logger.info("pgvector extension verified")

def main():
    logger.info("Starting local data ingestion process...")

    # 1. Load Text files and PDFs
    logger.info("Loading Text files and PDFs from data directory...")
    txt_loader = DirectoryLoader(DATA_DIR, glob="*.txt", loader_cls=TextLoader)
    txt_documents = txt_loader.load()
    logger.info(f"Loaded {len(txt_documents)} Text documents.")

    pdf_loader = DirectoryLoader(DATA_DIR, glob="*.pdf", loader_cls=PyPDFLoader)
    pdf_documents = pdf_loader.load()
    logger.info(f"Loaded {len(pdf_documents)} pages from PDFs.")

    all_docs = txt_documents + pdf_documents

    if not all_docs:
        logger.warning("No documents found to ingest!")
        return

    # 2. Chunk the documents
    logger.info("Chunking documents...")
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200,
        length_function=len
    )
    chunks = text_splitter.split_documents(all_docs)
    logger.info(f"Created {len(chunks)} text chunks.")

    # 3. Setup Bedrock Embeddings and PGVector
    region = os.environ.get("AWS_REGION", "eu-central-1")
    embeddings = BedrockEmbeddings(
        model_id="amazon.titan-embed-text-v2:0",
        region_name=region,
    )

    conn_string = get_db_connection_string()
    init_db(conn_string)

    vector_store = PGVector(
        embeddings=embeddings,
        collection_name="digital_twin_docs",
        connection=conn_string,
        use_jsonb=True,
    )

    # 4. Store in PostgreSQL
    logger.info("Generating embeddings via Amazon Bedrock and storing in PostgreSQL (pgvector)...")

    # Process in batches to avoid rate limits
    batch_size = 20
    for i in range(0, len(chunks), batch_size):
        batch = chunks[i:i+batch_size]
        logger.info(f"Processing batch {i//batch_size + 1}/{(len(chunks)-1)//batch_size + 1}...")

        vector_store.add_documents(batch)
        time.sleep(1) # Small delay to respect API rate limits

    logger.info(f"Successfully ingested all data into PostgreSQL Database.")

if __name__ == "__main__":
    main()
