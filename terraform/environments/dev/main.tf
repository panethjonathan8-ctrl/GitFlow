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

module "ec2" {
  source         = "../../modules/ec2"
  project        = var.project
  env            = var.env
  vpc_id         = module.vpc.vpc_id
  subnet_id      = module.vpc.public_subnet_ids[0]
  aws_region     = var.aws_region
  ecr_registry   = var.ecr_registry
  ecr_repo       = var.ecr_repo
  ec2_public_key = var.ec2_public_key
  # instance_type and allowed_cidr_blocks use module defaults
}

module "eks" {
  source       = "../../modules/eks"
  project      = var.project
  env          = var.env
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.public_subnet_ids
  desired_size = 1
  max_size     = 2
  # cluster_version, instance_types, min_size, capacity_type use module defaults
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
