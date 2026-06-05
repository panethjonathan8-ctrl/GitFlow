variable "project" {
  description = "Project name — used for naming IAM resources"
  type        = string
}

variable "env" {
  description = "Environment name — used for naming IAM resources"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — passed to the controller so it knows which cluster's Ingresses to watch"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — the controller needs this to create ALBs in the right VPC"
  type        = string
}

variable "aws_region" {
  description = "AWS region — the controller uses this to make regional API calls"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider — Federated principal in the controller's trust policy"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL — used to scope the trust policy to the controller's service account"
  type        = string
}

variable "chart_version" {
  description = "Version of the aws-load-balancer-controller Helm chart — pin to avoid unexpected upgrades"
  type        = string
  default     = "1.8.3"
  # Chart 1.8.3 = controller image v2.8.3
  # Check releases at: https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases
}
