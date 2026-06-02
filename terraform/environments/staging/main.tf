terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "gitflow-analyzer-tfstate-153772056450"
    key          = "staging/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    encrypt      = true
    # Same S3 bucket as dev but different key.
    # dev uses:     dev/terraform.tfstate
    # staging uses: staging/terraform.tfstate
    # They are completely separate state files so applying staging
    # never affects dev resources and vice versa.
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source              = "../../modules/vpc"
  project             = var.project
  env                 = var.env
  aws_region          = var.aws_region
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  # Overriding the CIDR defaults so staging gets 10.1.x.x
  # instead of the dev default 10.0.x.x
}

module "iam" {
  source          = "../../modules/iam"
  project         = var.project
  env             = var.env
  github_username = var.github_username
  github_repo     = "GitFlow"
  aws_account_id  = var.aws_account_id
    create_oidc_provider = false
}


module "secrets" {
  source  = "../../modules/secrets"
  project = var.project
  env     = var.env
  # env = "staging" means secrets are stored as:
  # gitflow-analyzer/staging/github-token
  # Completely separate from gitflow-analyzer/dev/github-token
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
}
