terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
  source  = "../../modules/ecr"
  project = var.project
  # services and image_retention_count use the defaults defined in the module.
  # You only override them here if you need different values for this environment.
}

module "secrets" {
  source  = "../../modules/secrets"
  project = var.project
  env     = var.env
}
