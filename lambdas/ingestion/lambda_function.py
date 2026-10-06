import os
import json
import boto3
import sys
import urllib.parse
import re
import logging
from pathlib import Path

from langchain_community.document_loaders import PyPDFLoader, TextLoader
from langchain_aws import BedrockEmbeddings

# build.sh copies lambdas/shared/s3_vector_store.py to the zip root. Running the
# file locally it is two levels up, hence the append.
sys.path.append(str(Path(__file__).resolve().parent.parent / "shared"))
from s3_vector_store import S3VectorStore  # noqa: E402
from chunking import build_splitter  # noqa: E402

# ===========================================================================
# Structured JSON Logging (mirrors the API Lambda pattern)
# ===========================================================================

# Standard LogRecord attributes — anything else on the record came in via
# `extra=` and should be included in the JSON output.
_STANDARD_LOG_ATTRS = set(vars(logging.makeLogRecord({})).keys()) | {"message", "asctime"}


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        import json as _json
        log_obj = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Surface extra= fields (key, chunk counts, ...) so they are queryable
        for k, v in record.__dict__.items():
            if k not in _STANDARD_LOG_ATTRS and not k.startswith("_"):
                log_obj[k] = v if isinstance(v, (str, int, float, bool, type(None))) else str(v)
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return _json.dumps(log_obj)

_handler = logging.StreamHandler()
_handler.setFormatter(JSONFormatter())
# force=True: the Lambda runtime pre-installs a root handler, which makes a
# plain basicConfig() a silent no-op — INFO logs were dropped entirely and the
# JSON formatter never ran. force removes the runtime handler first.
logging.basicConfig(level=logging.INFO, handlers=[_handler], force=True)
logger = logging.getLogger("digital-twin-ingestion")

# ===========================================================================
# AWS Clients
# ===========================================================================

s3_client = boto3.client("s3")

# Allowed file extensions for ingestion — explicit allowlist (not blocklist)
ALLOWED_EXTENSIONS = {".pdf", ".txt", ".md"}
# Maximum filename length to prevent filesystem issues
MAX_FILENAME_LENGTH = 200


def build_vector_store(embeddings) -> S3VectorStore:
    """The S3 Vectors index this Lambda writes into.

    No credentials and no connection setup: the index is reached with the
    Lambda's own IAM role. The CREATE EXTENSION bootstrap and the Secrets
    Manager lookup that used to live here went away with the database.
    """
    bucket = os.environ["VECTOR_BUCKET_NAME"]
    index = os.environ["VECTOR_INDEX_NAME"]
    return S3VectorStore(
        client=boto3.client("s3vectors"),
        vector_bucket_name=bucket,
        index_name=index,
        embedding=embeddings,
    )


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
        model_id=os.environ.get("BEDROCK_EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0"),
        region_name=region,
    )

    # 2. Setup Vector Store
    vector_store = build_vector_store(embeddings)

    # 3. Process each S3 record
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        raw_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        event_name = record.get("eventName", "")
        logger.info("Processing S3 record", extra={"bucket": bucket, "key": raw_key, "event": event_name})

        # Deletion: purge this file's vectors and move on. The bucket is
        # versioned, so `aws s3 sync --delete` emits ObjectRemoved:DeleteMarkerCreated
        # (not ObjectRemoved:Delete) — match the whole ObjectRemoved family.
        if event_name.startswith("ObjectRemoved"):
            deleted = vector_store.delete_by_source_key(raw_key)
            logger.info("Object removed from S3 — purged its vectors",
                        extra={"key": raw_key, "chunks_deleted": deleted})
            continue

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

            # 5. Split into chunks. Parameters come from lambdas/shared/chunking.py
            # so the local ingester cannot drift to a different chunk shape.
            chunks = build_splitter().split_documents(docs)
            logger.info("Split into chunks", extra={"chunk_count": len(chunks)})

            # Enrich metadata
            for chunk in chunks:
                chunk.metadata["source_key"] = raw_key
                chunk.metadata["bucket"] = bucket

            # 6. Upsert: purge any chunks from a previous version of this file
            # first, so re-ingestion replaces instead of duplicating. Vector keys
            # are "<s3 key>#<chunk index>", so a file that keeps the same chunk
            # count would overwrite in place anyway — but a file that shrinks
            # would leave orphans behind without this.
            purged = vector_store.delete_by_source_key(raw_key)
            if purged:
                logger.info("Purged old chunks before re-ingest",
                            extra={"key": raw_key, "chunks_deleted": purged})
            vector_store.add_documents(chunks)
            logger.info("Stored chunks in S3 Vectors", extra={"chunk_count": len(chunks)})

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
