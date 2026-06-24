# ===========================================================================
# RDS PostgreSQL with pgvector — Enterprise-grade vector database
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

  allocated_storage = 20  # Free tier limit
  storage_type      = "gp2"
  storage_encrypted = true # AWS KMS encryption at rest

  db_name  = "digitaltwin"
  username = "postgres"

  # AWS Secrets Manager auto-manages the master password
  # This keeps the password OUT of Terraform state entirely
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false # NEVER expose to internet
  skip_final_snapshot = true  # For development — change for production

  tags = { Name = "${var.project_name}-postgres" }
}
