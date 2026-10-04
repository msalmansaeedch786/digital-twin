# ===========================================================================
# S3 Vectors — vector store for the RAG knowledge base
# ===========================================================================
# Replaces RDS PostgreSQL + pgvector. The reason is cost, not capability:
# measured over Sep 1 - Oct 4, RDS was 47.6% of the bill and the VPC interface
# endpoints another 50.2%, while Bedrock — the actual AI — was $0.00. Those two
# line items are one decision, because the endpoints exist only so a
# VPC-attached Lambda can reach Bedrock and Secrets Manager, and the Lambda is
# only in the VPC to reach RDS. Dropping the database lets both go.
#
# Retrieval latency is not a concern here: pgvector's search_ms measured 12.6 ms
# median against a 1057 ms chain, i.e. 1.2%. See scripts/eval/ for the recorded
# baseline this migration is checked against.

resource "aws_s3vectors_vector_bucket" "knowledge_base" {
  vector_bucket_name = "${var.project_name}-vectors-${random_string.bucket_suffix.result}"

  # Vectors are derived data — every one is reproducible by re-running ingestion
  # over the knowledge-base bucket. Nothing here is a source of truth, so a
  # destroy should not need a manual emptying step first.
  force_destroy = true

  tags = { Name = "${var.project_name}-vectors" }

  # Bootstrap ordering, not a logical dependency. The first apply of this stack
  # failed with AccessDeniedException: the GitHub Actions deploy role had no
  # s3vectors permissions, and Terraform saw no reason to update that policy
  # before trying to create the bucket. Forcing the order means one apply can do
  # both. Once the policy is in place this is a no-op.
  depends_on = [aws_iam_policy.github_actions_policy]
}

resource "aws_s3vectors_index" "documents" {
  vector_bucket_name = aws_s3vectors_vector_bucket.knowledge_base.vector_bucket_name
  index_name         = var.vector_index_name

  data_type = "float32"

  # Titan Text Embeddings v2 returns 1024 floats (verified against the live
  # model, not assumed). The dimension is fixed at creation: changing the
  # embedding model later means a new index, because vectors written by one
  # model are not searchable by another.
  dimension = 1024

  # Matches what pgvector was doing, so relevance ordering carries over rather
  # than silently changing along with the storage engine.
  distance_metric = "cosine"

  metadata_configuration {
    # The chunk text rides along as metadata so retrieval can return it without
    # a second lookup. Declared non-filterable because filterable metadata has a
    # far smaller size budget and nothing ever filters on the prose itself.
    non_filterable_metadata_keys = ["_page_content"]
  }

  tags = { Name = "${var.project_name}-documents" }
}
