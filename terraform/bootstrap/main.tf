terraform {
  required_version = ">= 1.10.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block here on purpose.
  # This module stores its own state locally — it's the thing that creates the backend.
  # All other modules will use the S3 backend this creates.
}

provider "aws" {
  region = var.aws_region
}

# ── S3 bucket for Terraform state ─────────────────────────────────────────────

resource "aws_s3_bucket" "tfstate" {
  # Include account ID to guarantee global uniqueness
  bucket = "${var.project}-tfstate-${var.aws_account_id}"

  # Prevent accidental deletion of state
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
    # Versioning means every state update is saved.
    # If Terraform corrupts or overwrites state, you can roll back.
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # State files can contain sensitive outputs (passwords, tokens from resources).
      # Encryption at rest is non-negotiable.
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  # All four set to true — the state bucket must never be publicly reachable.
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
# ── DynamoDB table for state locking ──────────────────────────────────────────

resource "aws_dynamodb_table" "tflock" {
  name         = "${var.project}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  # PAY_PER_REQUEST = you pay per lock/unlock operation, not for provisioned capacity.
  # A capstone project might use this table a few hundred times total — cost is cents.

  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
  # The LockID is the only attribute Terraform needs.
  # When a terraform apply runs, it writes a row here first.
  # If another apply tries to run simultaneously, it sees the row and aborts.
  # This prevents two CI jobs from corrupting state by writing at the same time.

  lifecycle {
    prevent_destroy = true
  }
}