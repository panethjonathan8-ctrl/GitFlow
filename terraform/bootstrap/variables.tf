variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name, used as a prefix on all resources"
  type        = string
  default     = "gitflow-analyzer"
}

variable "aws_account_id" {
  description = "Your AWS account ID — used to make the S3 bucket name globally unique"
  type        = string
  default     = "153772056450"
  # No default — must be provided, never hardcoded
}
