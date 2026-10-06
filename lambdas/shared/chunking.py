"""Chunking parameters shared by both ingestion paths.

There are two ingesters and there have to be: lambdas/ingestion/lambda_function.py
runs in Lambda on an S3 event, and lambdas/api/ingest.py is a local one-shot over
data/. They load documents differently — one from a downloaded temp file, one from
a directory — so they are not reducible to a single function without making both
worse.

What they MUST agree on is how text is split, because chunk boundaries decide what
retrieval can return. If the deployed ingester used 1000/200 and the local one used
800/100, re-running the local script would silently rewrite the index with
differently-shaped chunks, and the only symptom would be answers getting vaguer.

So the parameters live here once, and both import them. The loading stays separate,
the splitting cannot drift.
"""

from langchain_text_splitters import RecursiveCharacterTextSplitter

# 1000 characters with 200 of overlap. The overlap matters more than it looks:
# without it a fact split across a boundary ("AWS Certified Solutions Architect" /
# "- Professional") becomes unretrievable by either half.
CHUNK_SIZE = 1000
CHUNK_OVERLAP = 200

# Metadata key carrying the S3 object key (or local filename). The vector key is
# derived from it as "<source_key>#<chunk index>", which is what makes re-ingesting
# a file replace its own vectors instead of duplicating them.
SOURCE_KEY_FIELD = "source_key"


def build_splitter() -> RecursiveCharacterTextSplitter:
    """The one splitter configuration both ingestion paths use."""
    return RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        length_function=len,
    )
