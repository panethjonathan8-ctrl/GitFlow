variable "project" {
  description = "Project name used as a prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name — dev, staging"
  type        = string
}

variable "argocd_hostname" {
  description = "Public hostname for ArgoCD — must match the CloudFront alias and GoDaddy CNAME record"
  type        = string
  default     = "argocd.gitflow.space"
}

variable "alb_dns_name" {
  description = "DNS name of the shared ALB — used as the CloudFront origin for the ArgoCD distribution"
  type        = string
}
