# ── OIDC Provider ─────────────────────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  # This tells AWS to trust JWT tokens issued by GitHub Actions.
  # Without this, AWS has no idea who GitHub is and will reject all requests.
  count = var.create_oidc_provider ? 1 : 0

  client_id_list = ["sts.amazonaws.com"]
  # This says the tokens are intended for AWS STS specifically.
  # STS is the service that issues temporary credentials.

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  # This is GitHub's TLS certificate thumbprint.
  # AWS uses it to verify the token actually came from GitHub and not an impersonator.
  # This value is fixed and published by GitHub — it does not change often.
}
# ── IAM Role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
          # The principal is the OIDC provider, not a user or service.
          # This means only tokens from GitHub can trigger this assume role.
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # This is the critical security line.
            # Only YOUR specific repo on YOUR GitHub account can assume this role.
            # If anyone else tries from a different repo, AWS rejects it.
            # The :ref:refs/heads/* part means any branch can trigger it.
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_username}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── Policy: ECR access ────────────────────────────────────────────────────────
resource "aws_iam_role_policy" "ecr" {
  name = "ecr-push-pull"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
        # GetAuthorizationToken cannot be scoped to a specific repo —
        # it must be * because it returns a token for the whole registry.
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        # Scoped to only your project's ECR repos — not every repo in the account.
        Resource = "arn:aws:ecr:*:${var.aws_account_id}:repository/${var.project}/*"
      }
    ]
  })
}

# ── Policy: Terraform state access ────────────────────────────────────────────
resource "aws_iam_role_policy" "terraform_state" {
  name = "terraform-state"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        # Scoped to only your state bucket — not every S3 bucket in the account.
        Resource = [
          "arn:aws:s3:::${var.project}-tfstate-${var.aws_account_id}",
          "arn:aws:s3:::${var.project}-tfstate-${var.aws_account_id}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "terraform_infra" {
  name = "terraform-infra"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EC2VPC"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      {
        Sid      = "EKS"
        Effect   = "Allow"
        Action   = ["eks:*"]
        Resource = "*"
      },
      {
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:GetLifecyclePolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:ListTagsForResource",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:PutLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:TagResource",
          "ecr:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:ListSecrets",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:TagResource",
          "secretsmanager:UpdateSecret"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMForTerraform"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PassRole",
          "iam:TagRole",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:GetInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:ListInstanceProfilesForRole",
          "iam:ListInstanceProfiles"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBRead"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        # Required by terraform plan — data "aws_lb" looks up the ALB by tags
        # to get its DNS name for the CloudFront origin. Read-only: Terraform
        # does not create or modify the ALB (the LB Controller does that).
        Resource = "*"
      },
      {
        Sid    = "STSRead"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Policy: Frontend S3 + CloudFront ─────────────────────────────────────────
resource "aws_iam_role_policy" "frontend_cdn" {
  name = "frontend-cdn-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FrontendS3"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketVersioning",
          "s3:GetBucketTagging",
          "s3:GetBucketLocation",
          "s3:CreateBucket",
          "s3:DeleteBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-frontend-*",
          "arn:aws:s3:::${var.project}-frontend-*/*"
        ]
      },
      {
        Sid    = "CloudFrontManage"
        Effect = "Allow"
        # cloudfront:* avoids repeated whack-a-mole as Terraform adds new read
        # actions (e.g. ListTagsForResource) across provider versions.
        # CloudFront does not support resource-level ARNs, so Resource: * is required.
        Action   = ["cloudfront:*"]
        Resource = "*"
      },
      {
        Sid    = "SSMParameterReadWrite"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:ListTagsForResource"
        ]
        # Scoped to this project's parameters only.
        Resource = "arn:aws:ssm:*:${var.aws_account_id}:parameter/${var.project}/*"
      },
      {
        Sid    = "SSMDescribe"
        Effect = "Allow"
        Action = ["ssm:DescribeParameters"]
        # DescribeParameters cannot be scoped below account level — AWS
        # requires Resource: * for this list/filter action.
        Resource = "*"
      },
      {
        Sid    = "FrontendS3BucketRead"
        Effect = "Allow"
        Action = ["s3:Get*", "s3:List*"]
        # Covers every read operation Terraform needs during plan
        # (ACL, accelerate config, encryption, versioning, policy, etc.)
        # Scoped to the frontend bucket only.
        Resource = [
          "arn:aws:s3:::${var.project}-frontend-*",
          "arn:aws:s3:::${var.project}-frontend-*/*"
        ]
      }
    ]
  })
}

# ── Policy: ACM certificate management ───────────────────────────────────────
# Required for the frontend_cdn module which creates an ACM certificate in
# us-east-1 for CloudFront. Without these, terraform plan fails with
# AccessDeniedException when it tries to read the certificate state.
resource "aws_iam_role_policy" "acm" {
  name = "acm-certificate"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ACMManage"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:DeleteCertificate",
          "acm:GetCertificate",
          "acm:ListTagsForCertificate",
          "acm:AddTagsToCertificate"
        ]
        Resource = "*"
        # ACM does not support resource-level scoping for most actions —
        # AWS requires Resource: * for certificate operations.
      }
    ]
  })
}

# ── Policy: RDS (PostgreSQL for result caching) ───────────────────────────────
resource "aws_iam_role_policy" "rds" {
  name = "rds-manage"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSDescribe"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBSubnetGroups",
          "rds:DescribeDBParameterGroups",
          "rds:DescribeDBEngineVersions",
          "rds:DescribeOrderableDBInstanceOptions",
          "rds:ListTagsForResource"
        ]
        # AWS does not support resource-level ARNs for Describe actions —
        # they must be Resource: * or the calls are rejected.
        Resource = "*"
      },
      {
        Sid    = "RDSManage"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance",
          "rds:ModifyDBInstance",
          "rds:DeleteDBInstance",
          "rds:CreateDBSubnetGroup",
          "rds:ModifyDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource"
        ]
        # Scoped to this project's DB instances and subnet groups only.
        Resource = [
          "arn:aws:rds:*:${var.aws_account_id}:db:${var.project}-*",
          "arn:aws:rds:*:${var.aws_account_id}:subgrp:${var.project}-*"
        ]
      }
    ]
  })
}

# ── Policy: SSM for EC2 remote commands ───────────────────────────────────────
resource "aws_iam_role_policy" "ssm" {
  name = "ssm-ec2-commands"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMSendCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = "*"
        # SSM SendCommand lets GitHub Actions run a shell command
        # on the EC2 instance without SSH keys or open port 22.
        # The command runs as if you typed it directly on the instance.
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
        # Needed to find the instance ID by its tags
        # so the workflow knows which instance to deploy to.
      }
    ]
  })
}

