# ── DB Subnet Group ───────────────────────────────────────────────────────────
# A DB subnet group tells RDS which subnets it may place the instance in.
# RDS requires at least two subnets in different AZs — even for a single-AZ
# instance — so it can fail over if needed.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.env}"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project}-${var.env}-db-subnet-group"
    Project     = var.project
    Environment = var.env
  }
}

# ── Security Group ────────────────────────────────────────────────────────────
# Allows port 5432 (PostgreSQL) inbound only from the EKS node security group.
# Everything else — including the public internet — is denied by default.
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.env}-rds"
  description = "Allow PostgreSQL access from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    # Referencing the EKS node SG directly means only pods running on those
    # nodes can reach the database. A CIDR-based rule would be broader.
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # RDS needs outbound for DNS resolution and AWS internal traffic.
  }

  tags = {
    Name        = "${var.project}-${var.env}-rds-sg"
    Project     = var.project
    Environment = var.env
  }
}

# ── DB Password in Secrets Manager ───────────────────────────────────────────
# Terraform generates a random password and stores it in Secrets Manager.
# The app fetches it at runtime via boto3 — the password never appears in
# environment variables, Helm values, or container images.
resource "random_password" "db" {
  length  = 32
  special = false
  # special = false avoids characters that break PostgreSQL connection strings
  # (e.g. @, /, ?) without requiring URL encoding.
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project}/${var.env}/db-password"
  recovery_window_in_days = 0
  # recovery_window_in_days = 0 allows immediate deletion during terraform destroy.
  # The default (30 days) would block re-creating the secret with the same name.

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

# ── RDS Instance ──────────────────────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier = "${var.project}-${var.env}"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"
  # db.t3.micro is free-tier eligible (750 hours/month for 12 months).
  # After free tier: ~$15/month.

  allocated_storage = 20
  # 20 GB is the minimum for RDS and is included in the free tier.

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  # Never expose RDS to the internet — it lives in private subnets and
  # is reachable only from within the VPC.

  skip_final_snapshot = true
  # skip_final_snapshot = true means terraform destroy won't block waiting
  # for a snapshot. Fine for a dev database — set to false for production.

  tags = {
    Name        = "${var.project}-${var.env}-postgres"
    Project     = var.project
    Environment = var.env
  }
}
