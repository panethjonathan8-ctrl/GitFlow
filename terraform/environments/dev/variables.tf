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
  default     = "dev"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "github_username" {
  description = "Your GitHub username"
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry URL"
  type        = string
  default     = "153772056450.dkr.ecr.eu-west-1.amazonaws.com"
}

variable "ecr_repo" {
  description = "ECR repository URL for the analyzer image"
  type        = string
  default     = "153772056450.dkr.ecr.eu-west-1.amazonaws.com/gitflow-analyzer/analyzer"
}
