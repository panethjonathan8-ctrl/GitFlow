variable "project" {
  description = "Project name — used for naming the IAM role"
  type        = string
}

variable "env" {
  description = "Environment name — used for naming the IAM role"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider — the Federated principal in the trust policy"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster — used to scope the trust to a specific service account"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the service account lives in"
  type        = string
  default     = "gitflow-analyzer"
}

variable "service_account_name" {
  description = "Kubernetes service account allowed to assume this role"
  type        = string
  default     = "gitflow-analyzer"
}
