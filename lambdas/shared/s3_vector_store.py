"""A minimal LangChain VectorStore backed by Amazon S3 Vectors.

Why hand-written instead of langchain_aws.AmazonS3Vectors: that class exists and
works, but it landed in langchain-aws 1.x, which requires langchain-core >= 1.6
and pydantic >= 2.10. This stack is pinned to the langchain-core 0.3 line with
pydantic 2.7.4, so adopting it would drag a framework major-version upgrade
through the whole RAG chain in order to change where vectors are stored. The
boto3 "s3vectors" client is already present in the bundled botocore (1.43.36),
so this file needs no new dependency at all.

Only what the chain actually uses is implemented: embed, similarity search,
add, and delete. Deliberately not a general-purpose store.

Keys are deterministic: "<s3 object key>#<chunk index>". That is what makes a
re-upload idempotent — S3 Vectors can only delete by key, never by metadata
filter, so the key has to carry the identity of the source file.
"""

from __future__ import annotations

import logging
from typing import Any, Iterable, List, Optional

from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings
from langchain_core.vectorstores import VectorStore

logger = logging.getLogger(__name__)

# put_vectors accepts a batch; the knowledge base is small enough that this is
# really just a guard against a pathologically large single file.
PUT_BATCH = 200
DELETE_BATCH = 200

# Chunk text is stored as metadata alongside the vector. It is declared
# non-filterable at index creation time: filterable metadata carries a much
# smaller size budget, and nothing ever filters on the prose itself.
PAGE_CONTENT_KEY = "_page_content"
SOURCE_KEY = "source_key"


class S3VectorStore(VectorStore):
    """LangChain VectorStore over one S3 Vectors index."""

    def __init__(
        self,
        *,
        client: Any,
        vector_bucket_name: str,
        index_name: str,
        embedding: Embeddings,
        page_content_key: str = PAGE_CONTENT_KEY,
        source_key_field: str = SOURCE_KEY,
    ) -> None:
        self.client = client
        self.vector_bucket_name = vector_bucket_name
        self.index_name = index_name
        self._embedding = embedding
        self.page_content_key = page_content_key
        self.source_key_field = source_key_field

    # ---- LangChain plumbing -------------------------------------------------

    @property
    def embeddings(self) -> Embeddings:
        return self._embedding

    def _target(self) -> dict:
        return {"vectorBucketName": self.vector_bucket_name, "indexName": self.index_name}

    def _to_document(self, hit: dict) -> Document:
        metadata = dict(hit.get("metadata") or {})
        text = metadata.pop(self.page_content_key, "")
        metadata["vector_key"] = hit["key"]
        if "distance" in hit:
            metadata["distance"] = hit["distance"]
        return Document(page_content=text, metadata=metadata)

    def _select_relevance_score_fn(self):
        # The index is created with distanceMetric=cosine, so S3 Vectors returns
        # a cosine DISTANCE in [0, 2]. LangChain wants a 0..1 similarity.
        return lambda distance: max(0.0, min(1.0, 1.0 - distance))

    # ---- writes -------------------------------------------------------------

    def add_texts(
        self,
        texts: Iterable[str],
        metadatas: Optional[List[dict]] = None,
        *,
        ids: Optional[List[str]] = None,
        **kwargs: Any,
    ) -> List[str]:
        texts = list(texts)
        if not texts:
            return []
        metadatas = metadatas or [{} for _ in texts]
        if len(metadatas) != len(texts):
            raise ValueError("metadatas must be the same length as texts")

        # VectorStore.add_documents forwards ids whenever ANY document carries
        # one, filling the rest with None. A None would become the literal vector
        # key "None", so fall back to deriving unless every id is present.
        if ids is not None and len(ids) != len(texts):
            raise ValueError("ids must be the same length as texts")
        keys = list(ids) if ids and all(ids) else self._derive_keys(metadatas)

        vectors = self._embedding.embed_documents(texts)
        payload = [
            {
                "key": key,
                "data": {"float32": [float(x) for x in vector]},
                "metadata": {**metadata, self.page_content_key: text},
            }
            for key, text, metadata, vector in zip(keys, texts, metadatas, vectors)
        ]

        for start in range(0, len(payload), PUT_BATCH):
            self.client.put_vectors(**self._target(), vectors=payload[start:start + PUT_BATCH])
        logger.info("wrote %d vectors to %s/%s", len(payload),
                    self.vector_bucket_name, self.index_name)
        return keys

    def _derive_keys(self, metadatas: List[dict]) -> List[str]:
        """"<source_key>#<n>", with n counted per source file within this call.

        Counting per source rather than globally is what lets a single file be
        re-ingested and overwrite exactly its own vectors: put_vectors replaces
        an existing key in place.
        """
        seen: dict[str, int] = {}
        keys = []
        for metadata in metadatas:
            source = metadata.get(self.source_key_field)
            if not source:
                raise ValueError(
                    f"every chunk needs metadata[{self.source_key_field!r}] so its vector key "
                    "can be derived; pass ids= explicitly otherwise")
            n = seen.get(source, 0)
            seen[source] = n + 1
            keys.append(f"{source}#{n}")
        return keys

    # ---- reads --------------------------------------------------------------

    def similarity_search(
        self, query: str, k: int = 5, *, filter: Optional[dict] = None, **kwargs: Any
    ) -> List[Document]:
        return [doc for doc, _ in self.similarity_search_with_score(query, k, filter=filter)]

    def similarity_search_with_score(
        self, query: str, k: int = 5, *, filter: Optional[dict] = None, **kwargs: Any
    ) -> List[tuple[Document, float]]:
        vector = self._embedding.embed_query(query)
        return self.similarity_search_by_vector_with_score(vector, k, filter=filter)

    def similarity_search_by_vector(
        self, embedding: List[float], k: int = 5, *, filter: Optional[dict] = None, **kwargs: Any
    ) -> List[Document]:
        return [doc for doc, _ in
                self.similarity_search_by_vector_with_score(embedding, k, filter=filter)]

    def similarity_search_by_vector_with_score(
        self, embedding: List[float], k: int = 5, *, filter: Optional[dict] = None
    ) -> List[tuple[Document, float]]:
        request = {
            **self._target(),
            "topK": k,
            "queryVector": {"float32": [float(x) for x in embedding]},
            "returnMetadata": True,
            "returnDistance": True,
        }
        if filter:
            request["filter"] = filter
        hits = self.client.query_vectors(**request).get("vectors", [])
        return [(self._to_document(h), float(h.get("distance", 0.0))) for h in hits]

    # ---- deletes ------------------------------------------------------------

    def delete(self, ids: Optional[List[str]] = None, **kwargs: Any) -> bool:
        """Delete specific vector keys. Absent keys are not an error."""
        if not ids:
            return True
        for start in range(0, len(ids), DELETE_BATCH):
            self.client.delete_vectors(**self._target(), keys=ids[start:start + DELETE_BATCH])
        return True

    def list_keys(self) -> List[str]:
        """Every key in the index.

        S3 Vectors' list_vectors has no prefix parameter, so this is a full scan.
        That is acceptable only because this index holds tens of vectors; it would
        need rethinking at a scale where a scan per ingested file is not free.
        """
        keys: List[str] = []
        token = None
        while True:
            request = {**self._target(), "returnData": False, "returnMetadata": False}
            if token:
                request["nextToken"] = token
            response = self.client.list_vectors(**request)
            keys.extend(v["key"] for v in response.get("vectors", []))
            token = response.get("nextToken")
            if not token:
                return keys

    def delete_by_source_key(self, source_key: str) -> int:
        """Remove every chunk that came from one S3 object. Returns the count.

        This is the replacement for the SQL
        `DELETE ... WHERE cmetadata->>'source_key' = %s`. S3 Vectors cannot delete
        by metadata filter, so identity has to come from the key instead: scan,
        match on the "<source>#<n>" prefix, delete those keys.
        """
        doomed = [k for k in self.list_keys() if k.rsplit("#", 1)[0] == source_key]
        if doomed:
            self.delete(doomed)
        return len(doomed)

    # ---- abstract-method obligation ----------------------------------------

    @classmethod
    def from_texts(
        cls,
        texts: List[str],
        embedding: Embeddings,
        metadatas: Optional[List[dict]] = None,
        **kwargs: Any,
    ) -> "S3VectorStore":
        store = cls(embedding=embedding, **kwargs)
        store.add_texts(texts, metadatas)
        return store
