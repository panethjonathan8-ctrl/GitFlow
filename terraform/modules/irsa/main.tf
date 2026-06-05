locals {
  oidc_host = replace(var.oidc_issuer_url, "https://", "")
  # IAM condition keys use the bare hostname, not the full URL.
  # e.g. oidc.eks.eu-west-1.amazonaws.com/id/ABC123
}

# ── Trust policy ──────────────────────────────────────────────────────────────
# This is the IRSA magic. It says: "the only identity allowed to assume this
# IAM role is the specific Kubernetes service account in the specific namespace."
# EKS injects a signed JWT into the pod, AWS validates it against the OIDC
# provider, and if the sub/aud claims match, it hands back temporary credentials.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
      # sub = the identity inside the JWT. Format is always:
      #   system:serviceaccount:<namespace>:<service-account-name>
      # Changing either the namespace or the SA name breaks the trust — intentionally.
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
      # aud = the intended audience of the token.
      # Without this condition, a token issued for one AWS service could be
      # replayed against another. Pinning to sts.amazonaws.com prevents that.
    }
  }
}

# ── App IAM role ──────────────────────────────────────────────────────────────
resource "aws_iam_role" "app" {
  name               = "${var.project}-${var.env}-app-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  # This replaces the node-level Secrets Manager policy in the EKS module.
  # Previously: every process on every node could access Secrets Manager.
  # Now: only pods running under this specific service account can.

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── Secrets Manager permission ────────────────────────────────────────────────
data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "ReadProjectSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:*:*:secret:${var.project}/*"]
    # Scoped to secrets under your project prefix only.
    # A compromised pod cannot read secrets belonging to other projects.
  }
}

resource "aws_iam_role_policy" "secrets_read" {
  name   = "secrets-manager-read"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.secrets_read.json
}
