terraform {
  required_version = ">= 1.10.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "gitflow-analyzer-tfstate-153772056450"
    key          = "dev/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    encrypt      = true
    # This is the remote backend you created in the bootstrap step.
    # From now on all state for the dev environment is stored here.
    # The key "dev/terraform.tfstate" means it gets its own file
    # separate from the bootstrap state.
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  # ACM certificates for CloudFront must live in us-east-1 — AWS hard requirement.
  # This alias is passed to the frontend_cdn module which creates the cert there.
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
  # Gets a short-lived (15 min) auth token using your existing AWS credentials.
  # This is the same token kubectl uses — no extra IAM permissions needed.
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.main.token
}

module "vpc" {
  source     = "../../modules/vpc"
  project    = var.project
  env        = var.env
  aws_region = var.aws_region
  # vpc_cidr and public_subnet_cidrs use the defaults defined in the module.
  # You only override them here if you need different values.
}

module "iam" {
  source          = "../../modules/iam"
  project         = var.project
  env             = var.env
  github_username = var.github_username
  github_repo     = "GitFlow"
  aws_account_id  = var.aws_account_id
}

module "ecr" {
  source   = "../../modules/ecr"
  project  = var.project
  services = ["analyzer", "graph-builder", "result-api"]
  # frontend removed — static files are now served from S3/CloudFront.
}

module "secrets" {
  source  = "../../modules/secrets"
  project = var.project
  env     = var.env
  # Creates gitflow-analyzer/dev/github-token in Secrets Manager.
  # Value is set manually: aws secretsmanager put-secret-value --secret-id ...
}

module "secrets_staging" {
  source  = "../../modules/secrets"
  project = var.project
  env     = "staging"
  # Creates gitflow-analyzer/staging/github-token.
  # After terraform apply, populate with the same GitHub token as dev.
}

module "secrets_production" {
  source  = "../../modules/secrets"
  project = var.project
  env     = "production"
  # Creates gitflow-analyzer/production/github-token.
  # After terraform apply, populate with the same GitHub token as dev.
}

module "eks" {
  source         = "../../modules/eks"
  project        = var.project
  env            = var.env
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.public_subnet_ids
  instance_types = ["t3a.large"]
  # t3a.large = 2 vCPU, 8 GB RAM — upgraded from t3a.medium to give
  # Prometheus + Grafana enough headroom alongside ArgoCD and the app pods.
  # Also raises the pod limit from 17 to ~36 (3 ENIs × 12 IPs per ENI).
  desired_size            = 2
  max_size                = 2
  github_actions_role_arn = module.iam.github_actions_role_arn
  # Grants the CI role Kubernetes API access so terraform plan/apply can
  # read and write Helm releases and Kubernetes resources from GitHub Actions.
}

module "argocd" {
  source          = "../../modules/argocd"
  project         = var.project
  env             = var.env
  cluster_name    = module.eks.cluster_name
  aws_region      = var.aws_region
  github_username = var.github_username

  depends_on = [module.eks]
  # ArgoCD can only be installed after the cluster and node group are fully
  # ready — depends_on enforces that order.
}

module "irsa" {
  source = "../../modules/irsa"

  project           = var.project
  env               = var.env
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  namespace         = "gitflow-analyzer-dev"
  # Explicit namespace — the trust policy scopes credentials to pods in THIS
  # namespace only. Renamed from "gitflow-analyzer" to "gitflow-analyzer-dev"
  # as part of the multi-env migration (issue #57).

  depends_on = [module.eks]
}

module "irsa_staging" {
  source = "../../modules/irsa"

  project           = var.project
  env               = "staging"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  namespace         = "gitflow-analyzer-staging"

  depends_on = [module.eks]
}

module "irsa_production" {
  source = "../../modules/irsa"

  project           = var.project
  env               = "production"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  namespace         = "gitflow-analyzer-production"

  depends_on = [module.eks]
}

module "aws_lb_controller" {
  source = "../../modules/aws-lb-controller"

  project           = var.project
  env               = var.env
  cluster_name      = module.eks.cluster_name
  vpc_id            = module.vpc.vpc_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url

  depends_on = [module.eks]
  # The controller needs the cluster to exist and the OIDC provider to be
  # registered before it can start.
}

# ── Frontend CDN ──────────────────────────────────────────────────────────────
# Two-layer design that survives nightly cluster teardown:
#
#   Layer 1 — data.aws_lb + aws_ssm_parameter (runs only when cluster is up)
#     Looks up the ALB by the tag the LB Controller puts on it, then writes
#     the DNS name into SSM Parameter Store. Uses the AWS provider only —
#     no Kubernetes dependency.
#
#   Layer 2 — data.aws_ssm_parameter + module.frontend_cdn (always works)
#     Reads the last-known ALB hostname from SSM. SSM retains the value
#     even after the cluster is destroyed, so terraform plan succeeds
#     overnight without a running cluster.
#
# When the cluster is UP:   apply writes the new ALB hostname to SSM and
#                           keeps CloudFront pointing at the right origin.
# When the cluster is DOWN: plan reads the stale SSM value — no changes
#                           to CloudFront, plan succeeds cleanly.

data "aws_lb" "app" {
  tags = {
    "elbv2.k8s.aws/cluster" = "${var.project}-${var.env}"
    "ingress.k8s.aws/stack" = "gitflow-analyzer"
  }
  # The AWS Load Balancer Controller tags every ALB it creates with these two
  # keys so we can find it by tag instead of by name (which changes on every
  # cluster recreation).
  #
  # The stack tag changed from "gitflow-analyzer/gitflow-analyzer" to
  # "gitflow-analyzer" when we added group.name to the Ingress. For a regular
  # Ingress the tag is "<namespace>/<name>"; for an IngressGroup it is just the
  # group name. Both Ingress resources (gitflow-analyzer + Grafana) now use
  # group.name=gitflow-analyzer, so the LBC creates one shared ALB.
  depends_on = [module.aws_lb_controller, module.argocd]
  # Wait for the LB Controller and ArgoCD to be installed — the ALB is created
  # when ArgoCD syncs the Ingress resource, not by Terraform directly.
}

resource "aws_ssm_parameter" "alb_dns_name" {
  name  = "/${var.project}/${var.env}/alb-dns-name"
  type  = "String"
  value = data.aws_lb.app.dns_name

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

data "aws_ssm_parameter" "alb_dns_name" {
  name = "/${var.project}/${var.env}/alb-dns-name"
  # Reads the value written by aws_ssm_parameter.alb_dns_name above.
  # Because SSM is a durable store, this succeeds even when the cluster
  # (and the ALB) no longer exist.
  depends_on = [aws_ssm_parameter.alb_dns_name]
}

module "frontend_cdn" {
  source = "../../modules/frontend-cdn"

  project      = var.project
  env          = var.env
  alb_dns_name = data.aws_ssm_parameter.alb_dns_name.value
  domain_name  = "gitflow.space"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

module "rds" {
  source = "../../modules/rds"

  project            = var.project
  env                = var.env
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  # No depends_on or EKS reference here. The VPC dependency is implicit via
  # vpc_id and private_subnet_ids. The EKS → RDS port 5432 rule is managed
  # by the standalone resource below so RDS survives nightly EKS teardowns.
}

# ── EKS → RDS access rule ─────────────────────────────────────────────────────
# Allows pods on EKS nodes to connect to PostgreSQL on port 5432.
# Lives here (not inside module.rds) so it is destroyed and recreated with
# the EKS cluster. The RDS instance and its security group are unaffected.
resource "aws_security_group_rule" "eks_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_security_group_id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "PostgreSQL from EKS nodes"
}

module "monitoring" {
  source = "../../modules/monitoring"

  project                    = var.project
  env                        = var.env
  grafana_admin_password     = var.grafana_admin_password
  github_oauth_client_id     = var.github_oauth_client_id
  github_oauth_client_secret = var.github_oauth_client_secret
  github_oauth_allowed_user  = var.github_oauth_allowed_user
  alb_dns_name               = data.aws_ssm_parameter.alb_dns_name.value
  # grafana_hostname uses module default (grafana.gitflow.space)

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  depends_on = [module.eks, module.argocd]
}
# tested CI pipeline
