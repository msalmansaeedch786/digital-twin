import os
import json
import boto3
import urllib.parse
import re
import logging

from langchain_community.document_loaders import PyPDFLoader, TextLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_aws import BedrockEmbeddings
from langchain_postgres import PGVector
import psycopg

# ===========================================================================
# Structured JSON Logging (mirrors the API Lambda pattern)
# ===========================================================================

class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        import json as _json
        log_obj = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return _json.dumps(log_obj)

_handler = logging.StreamHandler()
_handler.setFormatter(JSONFormatter())
logging.basicConfig(level=logging.INFO, handlers=[_handler])
logger = logging.getLogger("digital-twin-ingestion")

# ===========================================================================
# AWS Clients
# ===========================================================================

s3_client = boto3.client("s3")
secrets_client = boto3.client("secretsmanager")

# Allowed file extensions for ingestion — explicit allowlist (not blocklist)
ALLOWED_EXTENSIONS = {".pdf", ".txt", ".md"}
# Maximum filename length to prevent filesystem issues
MAX_FILENAME_LENGTH = 200


def get_db_connection_string():
    secret_arn = os.environ["DB_SECRET_ARN"]
    db_host = os.environ["DB_HOST"]
    db_name = os.environ["DB_NAME"]

    response = secrets_client.get_secret_value(SecretId=secret_arn)
    secret = json.loads(response["SecretString"])

    username = secret["username"]
    password = urllib.parse.quote_plus(secret["password"])
    return f"postgresql+psycopg://{username}:{password}@{db_host}:5432/{db_name}"


def init_db(connection_string: str):
    """Ensure pgvector extension exists. Idempotent."""
    raw_conn_string = connection_string.replace("postgresql+psycopg://", "postgresql://")
    with psycopg.connect(raw_conn_string, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    logger.info("pgvector extension verified")


def safe_filename(key: str) -> str:
    """
    Sanitize an S3 object key to a safe local filename.

    Security: Prevents path traversal attacks where a malicious S3 object name
    like '../../etc/passwd' could write outside /tmp. We:
    1. Extract only the basename (strip any directory components)
    2. Remove any character that isn't alphanumeric, dash, underscore, or dot
    3. Enforce a maximum length
    4. Verify the resulting extension is in our allowlist

    Returns the sanitized filename or raises ValueError if unsafe.
    """
    basename = os.path.basename(key)

    # Strip directory traversal sequences just in case basename isn't enough
    basename = basename.replace("..", "").lstrip("/").lstrip("\\")

    # Keep only safe characters: letters, digits, dash, underscore, dot
    sanitized = re.sub(r"[^a-zA-Z0-9._-]", "_", basename)

    # Enforce max length
    if len(sanitized) > MAX_FILENAME_LENGTH:
        sanitized = sanitized[:MAX_FILENAME_LENGTH]

    # Verify extension is in allowlist
    _, ext = os.path.splitext(sanitized)
    if ext.lower() not in ALLOWED_EXTENSIONS:
        raise ValueError(f"Unsupported file extension: {ext!r} for key {key!r}")

    if not sanitized:
        raise ValueError(f"Could not derive safe filename from key: {key!r}")

    return sanitized


def lambda_handler(event, context):
    logger.info("Ingestion Lambda invoked", extra={"record_count": len(event.get("Records", []))})

    # 1. Setup Bedrock embeddings
    region = os.environ.get("AWS_REGION", "eu-central-1")
    embeddings = BedrockEmbeddings(
        model_id="amazon.titan-embed-text-v2:0",
        region_name=region,
    )

    # 2. Setup Vector Store
    conn_string = get_db_connection_string()
    init_db(conn_string)

    vector_store = PGVector(
        embeddings=embeddings,
        collection_name="digital_twin_docs",
        connection=conn_string,
        use_jsonb=True,
    )

    # 3. Process each S3 record
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        raw_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        logger.info("Processing S3 object", extra={"bucket": bucket, "key": raw_key})

        tmp_path = None
        try:
            # Sanitize filename before writing to /tmp (path traversal fix)
            safe_name = safe_filename(raw_key)
            tmp_path = f"/tmp/{safe_name}"

            # Download from S3 to tmp
            s3_client.download_file(bucket, raw_key, tmp_path)
            logger.info("Downloaded S3 object", extra={"tmp_path": tmp_path})

            # 4. Load document
            _, ext = os.path.splitext(safe_name)
            if ext.lower() == ".pdf":
                loader = PyPDFLoader(tmp_path)
            else:
                loader = TextLoader(tmp_path, encoding="utf-8")

            docs = loader.load()
            logger.info("Loaded document", extra={"doc_count": len(docs)})

            # 5. Split into chunks
            text_splitter = RecursiveCharacterTextSplitter(
                chunk_size=1000,
                chunk_overlap=200,
                length_function=len,
            )
            chunks = text_splitter.split_documents(docs)
            logger.info("Split into chunks", extra={"chunk_count": len(chunks)})

            # Enrich metadata
            for chunk in chunks:
                chunk.metadata["source_key"] = raw_key
                chunk.metadata["bucket"] = bucket

            # 6. Store in PGVector
            vector_store.add_documents(chunks)
            logger.info("Stored chunks in pgvector", extra={"chunk_count": len(chunks)})

        except ValueError as e:
            # Invalid/unsafe file — log and skip (don't crash the whole batch)
            logger.warning("Skipping invalid file", extra={"key": raw_key, "reason": str(e)})
            continue
        except Exception:
            logger.error("Error processing S3 object", extra={"key": raw_key}, exc_info=True)
            raise  # Re-raise to trigger Lambda retry / DLQ
        finally:
            # Always clean up temp file
            if tmp_path and os.path.exists(tmp_path):
                os.remove(tmp_path)
                logger.info("Cleaned up temp file", extra={"tmp_path": tmp_path})

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Ingestion complete", "records": len(event["Records"])}),
    }
