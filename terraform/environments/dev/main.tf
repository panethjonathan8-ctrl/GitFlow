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
  services = ["analyzer", "graph-builder", "result-api", "frontend"]
}

module "secrets" {
  source  = "../../modules/secrets"
  project = var.project
  env     = var.env
}

module "eks" {
  source         = "../../modules/eks"
  project        = var.project
  env            = var.env
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.public_subnet_ids
  instance_types = ["t3a.medium"]
  # t3a.medium = 2 vCPU, 4 GB RAM — AMD equivalent of t3.medium at ~$2/month cheaper.
  # Using t3a because t3.medium has a pending quota increase request with AWS.
  # Quota confirmed available via dry-run before applying.
  desired_size            = 1
  max_size                = 2
  github_actions_role_arn = module.iam.github_actions_role_arn
  # Grants the CI role Kubernetes API access so terraform plan/apply can
  # read and write Helm releases and Kubernetes resources from GitHub Actions.
}

module "argocd" {
  source       = "../../modules/argocd"
  project      = var.project
  env          = var.env
  cluster_name = module.eks.cluster_name

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
  # namespace and service_account_name use module defaults (gitflow-analyzer)

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
