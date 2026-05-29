resource "aws_secretsmanager_secret" "secrets" {
  for_each = toset(var.secret_names)
  # Creates one secret container per name in the list.

  name = "${var.project}/${var.env}/${each.key}"
  # Naming convention: project/env/name
  # e.g. gitflow-analyzer/dev/github-token
  # The slashes create a namespace — you can give IAM permissions
  # to gitflow-analyzer/* without touching secrets from other projects.

  recovery_window_in_days = 0
  # In dev, setting this to 0 means secrets can be deleted immediately.
  # In production you would set this to 30 — giving you a 30 day window
  # to recover an accidentally deleted secret.
  # For a dev environment immediate deletion is fine and saves confusion
  # when you are iterating quickly.

  tags = {
    Project     = var.project
    Environment = var.env
    Name        = "${var.project}/${var.env}/${each.key}"
  }
}

# ── IAM policy document for app to read secrets ───────────────────────────────
resource "aws_iam_policy" "read_secrets" {
  name        = "${var.project}-${var.env}-read-secrets"
  description = "Allows reading secrets scoped to this project and environment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadProjectSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.project}/${var.env}/*"
        # Scoped to only this project's secrets in this environment.
        # The app cannot read secrets from other projects or environments
        # even if it somehow gets this policy attached.
      }
    ]
  })
}
