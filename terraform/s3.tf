# ===========================================================================
# S3 Bucket — Knowledge Base for the Digital Twin
# ===========================================================================

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "knowledge_base" {
  bucket = "${var.project_name}-knowledge-base-${random_string.bucket_suffix.result}"
  tags   = { Name = "${var.project_name}-knowledge-base" }
}

# Enable versioning — allows recovery of accidentally deleted documents
resource "aws_s3_bucket_versioning" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Block ALL public access
resource "aws_s3_bucket_public_access_block" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
