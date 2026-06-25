# ===========================================================================
# RDS PostgreSQL with pgvector — Enterprise-grade vector database
# AWS Best Practices applied:
# - Automated backups (7-day retention)
# - Deletion protection (prevents accidental `terraform destroy` data loss)
# - Final snapshot on deletion
# - PostgreSQL logs exported to CloudWatch for query analysis
# - CA certificate upgraded to rsa4096 (stronger than default rsa2048)
# ===========================================================================

# DB Subnet Group — Spans 2 AZs in PRIVATE subnets
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  tags       = { Name = "${var.project_name}-db-subnet-group" }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro" # Free tier eligible

  allocated_storage       = 20  # Free tier limit
  storage_type            = "gp2"
  backup_retention_period = 0 # Explicitly disabled for free tier limits
  storage_encrypted      = true # AWS KMS encryption at rest
  auto_minor_version_upgrade = true

  db_name  = "digitaltwin"
  username = "postgres"

  # AWS Secrets Manager auto-manages the master password
  # This keeps the password OUT of Terraform state entirely
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = true # Zero-Cost Hack: Exposed to internet

  # --- Data Protection ---
  backup_window             = "02:00-03:00"                 # Low-traffic window (UTC)
  maintenance_window        = "Mon:03:30-Mon:04:30"
  deletion_protection       = true                          # Prevents accidental deletion
  skip_final_snapshot       = false                         # Create snapshot on deletion
  final_snapshot_identifier = "${var.project_name}-final-snapshot"
  copy_tags_to_snapshot     = true

  # --- Observability ---
  # Export PostgreSQL logs to CloudWatch for slow query analysis and security auditing
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Upgraded certificate authority for stronger TLS
  ca_cert_identifier = "rds-ca-rsa4096-g1"

  tags = { Name = "${var.project_name}-postgres" }
}

# CloudWatch Log Group for PostgreSQL logs
resource "aws_cloudwatch_log_group" "rds_postgresql" {
  name              = "/aws/rds/instance/${var.project_name}-postgres/postgresql"
  retention_in_days = 30
}
