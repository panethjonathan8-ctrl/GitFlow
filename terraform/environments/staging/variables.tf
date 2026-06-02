variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "gitflow-analyzer"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "staging"
  # This single variable change means every resource gets a different name.
  # The EC2 instance becomes gitflow-analyzer-staging-app,
  # the security group becomes gitflow-analyzer-staging-ec2-sg, etc.
  # Dev and staging resources never conflict with each other.
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "github_username" {
  description = "GitHub username"
  type        = string
}

variable "ec2_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry URL"
  type        = string
  default     = "153772056450.dkr.ecr.eu-west-1.amazonaws.com"
}

variable "ecr_repo" {
  description = "ECR repo URL for the analyzer image"
  type        = string
  default     = "153772056450.dkr.ecr.eu-west-1.amazonaws.com/gitflow-analyzer/analyzer"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
  # Different CIDR from dev (10.0.0.0/16).
  # This prevents IP conflicts if you ever need to peer the VPCs
  # or connect them via VPN. Always use different CIDRs per environment.
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  # Different from dev subnets (10.0.1.0/24, 10.0.2.0/24)
}
