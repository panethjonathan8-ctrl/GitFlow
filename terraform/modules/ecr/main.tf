# ── ECR Repositories ──────────────────────────────────────────────────────────
resource "aws_ecr_repository" "services" {
  for_each = toset(var.services)
  # for_each creates one repository per service in the list.
  # toset() converts the list to a set so Terraform can iterate over it.
  # This means adding a new service later is as simple as adding
  # its name to the services variable — no new resource blocks needed.

  name = "${var.project}/${each.key}"
  # Naming convention: project/service — e.g. gitflow-analyzer/analyzer
  # The slash creates a logical namespace in the ECR console
  # making it easy to see all repos belonging to this project.

  image_tag_mutability = "MUTABLE"
  # IMMUTABLE means once you push an image with a tag like "abc123",
  # you cannot overwrite it with a different image using the same tag.
  # This is critical for traceability — if something breaks in production
  # you need to be certain that tag always refers to the exact same image.
  # MUTABLE would let you overwrite :latest silently which makes debugging
  # nearly impossible.

  image_scanning_configuration {
    scan_on_push = true
    # Every time an image is pushed, ECR automatically scans it for
    # known CVEs (Common Vulnerabilities and Exposures) using the
    # open source Clair scanner.
    # This is free and catches things like: outdated base images,
    # vulnerable OS packages, known library exploits.
    # You see the results in the ECR console under each image.
  }

  encryption_configuration {
    encryption_type = "AES256"
    # Images are encrypted at rest in ECR storage.
    # AES256 is AWS managed encryption — free and automatic.
    # This means even if someone somehow accessed the raw S3 storage
    # behind ECR, they could not read your images.
  }

  tags = {
    Name    = "${var.project}/${each.key}"
    Project = var.project
    Service = each.key
  }
}

# ── Lifecycle policies ────────────────────────────────────────────────────────
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name
  # One lifecycle policy per repo — same iteration as the repos above.

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last ${var.image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = {
          type = "expire"
        }
        # When the number of images exceeds the retention count,
        # the oldest images are automatically deleted.
        # tagStatus = "any" means this applies to both tagged and untagged images.
        # Untagged images are typically leftover build cache layers
        # that serve no purpose and waste storage.
      }
    ]
  })
}

# ── Repository policies ───────────────────────────────────────────────────────
resource "aws_ecr_repository_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy"
        ]
        # This gives your entire AWS account access to these repos.
        # Any IAM user or role in account 153772056450 that has
        # ECR permissions in their IAM policy can access these repos.
        # This is correct — IAM policies still control the actual access,
        # this just says "account-level principals are eligible".
      }
    ]
  })
}

# ── Data source: current account ID ──────────────────────────────────────────
data "aws_caller_identity" "current" {}
# This fetches your account ID dynamically at plan time.
# Used in the repository policy above.
# Better than hardcoding the account ID in the module itself —
# if you reuse this module in a different account it still works.
