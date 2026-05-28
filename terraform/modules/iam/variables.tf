variable "project" {
  description = "Project name used as prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name — dev, staging, or prod"
  type        = string
}

variable "github_username" {
  description = "Your GitHub username"
  type        = string
  # Used to lock the OIDC role so only YOUR repo can assume it.
  # If someone else tries to use this role from their repo, AWS rejects it.
}

variable "github_repo" {
  description = "GitHub repository name without the username"
  type        = string
  default     = "gitflow-analyzer"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}
