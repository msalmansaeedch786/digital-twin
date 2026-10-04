#!/usr/bin/env python3
"""Integration test for S3VectorStore against real Amazon S3 Vectors.

It creates its own vector bucket and index, exercises the store, and tears
everything down again - including on failure. Needs AWS credentials; costs
fractions of a cent.

  lambdas/api/venv/bin/python lambdas/shared/test_s3_vector_store.py
"""
import sys, time, traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import boto3
from langchain_core.embeddings import Embeddings
from s3_vector_store import S3VectorStore

REGION = "eu-central-1"
DIM = 8

# Named rather than inlined below: a literal next to a field whose name ends in
# "_key" trips gitleaks' generic-api-key rule as a false positive.
EXPERIENCE = "02_experience.txt"
CERTS = "05_certifications.txt"
ABSENT = "99_does_not_exist.txt"
EDUCATION = "06_education.txt"

# Deterministic stand-in for Titan: every text gets a fixed unit-ish vector, so
# nearest-neighbour order is something the test can assert exactly.
VECTORS = {
    "thoughtworks senior consultant": [1, 0, 0, 0, 0, 0, 0, 0],
    "receeve devops engineer":        [0.9, 0.1, 0, 0, 0, 0, 0, 0],
    "six aws certifications":         [0, 1, 0, 0, 0, 0, 0, 0],
    "docker certified associate":     [0, 0.9, 0.1, 0, 0, 0, 0, 0],
    "punjab university cgpa":         [0, 0, 1, 0, 0, 0, 0, 0],
}


class FakeEmbeddings(Embeddings):
    def embed_documents(self, texts):
        return [self._one(t) for t in texts]

    def embed_query(self, text):
        return self._one(text)

    @staticmethod
    def _one(text):
        if text in VECTORS:
            return [float(x) for x in VECTORS[text]]
        # unknown text -> a direction nothing else occupies
        return [0.0] * (DIM - 1) + [1.0]


checks = []


def check(label, condition, detail=""):
    checks.append((label, bool(condition), detail))
    print(f"  [{'ok  ' if condition else 'FAIL'}] {label}" + (f"  <- {detail}" if detail and not condition else ""))


def run(store):
    print("\n1. add_texts derives '<source>#<n>' keys, counted per source file")
    texts = ["thoughtworks senior consultant", "receeve devops engineer",
             "six aws certifications", "docker certified associate"]
    metas = [{"source_key": EXPERIENCE}, {"source_key": EXPERIENCE},
             {"source_key": CERTS}, {"source_key": CERTS}]
    keys = store.add_texts(texts, metas)
    check("keys are per-source and zero-based",
          keys == [f"{EXPERIENCE}#0", f"{EXPERIENCE}#1",
                   f"{CERTS}#0", f"{CERTS}#1"], str(keys))

    print("\n2. similarity_search returns the nearest chunk first, with text intact")
    docs = store.similarity_search("thoughtworks senior consultant", k=2)
    check("top hit is the exact match", docs and docs[0].page_content == "thoughtworks senior consultant",
          docs[0].page_content if docs else "no docs")
    check("second hit is the near neighbour", len(docs) > 1 and docs[1].page_content == "receeve devops engineer",
          docs[1].page_content if len(docs) > 1 else "missing")
    check("source_key survives the round trip",
          docs and docs[0].metadata.get("source_key") == EXPERIENCE,
          str(docs[0].metadata) if docs else "")
    check("page_content key is not leaked into metadata",
          docs and "_page_content" not in docs[0].metadata)

    print("\n3. k is honoured")
    check("k=1 returns one doc", len(store.similarity_search("six aws certifications", k=1)) == 1)
    check("k=4 returns four docs", len(store.similarity_search("six aws certifications", k=4)) == 4)

    print("\n4. relevance score maps cosine distance into 0..1, descending")
    scored = store.similarity_search_with_relevance_scores("thoughtworks senior consultant", k=2)
    check("exact match scores ~1.0", scored and scored[0][1] > 0.99, f"{scored[0][1]:.4f}" if scored else "")
    check("scores are within 0..1", all(0.0 <= s <= 1.0 for _, s in scored), str([s for _, s in scored]))
    check("scores descend", len(scored) > 1 and scored[0][1] >= scored[1][1])

    print("\n5. metadata filter restricts the search")
    hits = store.similarity_search("thoughtworks senior consultant", k=4,
                                   filter={"source_key": {"$eq": CERTS}})
    check("only the filtered source comes back",
          hits and all(d.metadata["source_key"] == CERTS for d in hits),
          str([d.metadata.get("source_key") for d in hits]))

    print("\n6. re-ingesting one file overwrites its own vectors rather than duplicating")
    before = sorted(store.list_keys())
    store.add_texts(["thoughtworks senior consultant", "receeve devops engineer"],
                    [{"source_key": EXPERIENCE}, {"source_key": EXPERIENCE}])
    after = sorted(store.list_keys())
    check("key set is unchanged after re-ingest", before == after,
          f"{len(before)} -> {len(after)}")

    print("\n7. delete_by_source_key removes exactly one file's chunks")
    removed = store.delete_by_source_key(EXPERIENCE)
    check("reported two removals", removed == 2, str(removed))
    remaining = sorted(store.list_keys())
    check("only the other file's chunks remain",
          remaining == [f"{CERTS}#0", f"{CERTS}#1"], str(remaining))
    check("searching the deleted source finds nothing of it",
          all(d.metadata["source_key"] != EXPERIENCE
              for d in store.similarity_search("thoughtworks senior consultant", k=4)))

    print("\n8. purging an unknown source is a no-op, not an error")
    check("returns 0", store.delete_by_source_key(ABSENT) == 0)

    print("\n9. a chunk with no source_key is rejected loudly")
    try:
        store.add_texts(["orphan"], [{}])
        check("raises ValueError", False, "no exception raised")
    except ValueError as e:
        check("raises ValueError", "source_key" in str(e), str(e)[:80])

    print("\n10. add_documents (what the ingestion Lambda actually calls) derives keys too")
    from langchain_core.documents import Document
    store.add_documents([Document(page_content="punjab university cgpa",
                                  metadata={"source_key": EDUCATION})])
    check("Document without an id gets a derived key",
          f"{EDUCATION}#0" in store.list_keys(), str(store.list_keys()))

    print("\n11. a partial id list is ignored rather than writing a 'None' key")
    # VectorStore.add_documents sends ids=[id, None] when only one Document has
    # one. Taking that literally would create a vector keyed "None".
    store.add_texts(["six aws certifications", "docker certified associate"],
                    [{"source_key": CERTS}, {"source_key": CERTS}],
                    ids=["explicit-key", None])
    check("no 'None' key was created", "None" not in store.list_keys(), str(store.list_keys()))

    print("\n12. shorter-than-k index returns what exists instead of erroring")
    check("k larger than the index is fine",
          0 < len(store.similarity_search("six aws certifications", k=50)) < 50)


def main():
    client = boto3.client("s3vectors", region_name=REGION)
    bucket = f"dt-s3v-test-{int(time.time())}"
    index = "test-index"
    print(f"creating {bucket}/{index} (dimension {DIM}, cosine)")
    client.create_vector_bucket(vectorBucketName=bucket)
    try:
        client.create_index(vectorBucketName=bucket, indexName=index, dataType="float32",
                            dimension=DIM, distanceMetric="cosine",
                            metadataConfiguration={"nonFilterableMetadataKeys": ["_page_content"]})
        store = S3VectorStore(client=client, vector_bucket_name=bucket, index_name=index,
                              embedding=FakeEmbeddings())
        run(store)
    except Exception:
        traceback.print_exc()
        checks.append(("unexpected exception", False, ""))
    finally:
        print(f"\ntearing down {bucket}")
        try:
            client.delete_index(vectorBucketName=bucket, indexName=index)
        except Exception as e:                                   # noqa: BLE001
            print("  index delete:", e)
        try:
            client.delete_vector_bucket(vectorBucketName=bucket)
        except Exception as e:                                   # noqa: BLE001
            print("  bucket delete:", e)

    passed = sum(1 for _, ok, _ in checks if ok)
    print(f"\n{passed}/{len(checks)} checks passed")
    failed = [(l, d) for l, ok, d in checks if not ok]
    if failed:
        print("\nfailures:")
        for label, detail in failed:
            print(f"  - {label} {('(' + detail + ')') if detail else ''}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
