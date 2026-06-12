variable "project" {
  description = "Project name — used in resource names and tags"
  type        = string
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB that fronts result-api — CloudFront proxies /api/* here"
  type        = string
}

variable "domain_name" {
  description = "Apex domain for the CloudFront distribution (e.g. gitflow.space) — ACM certificate covers this and www.domain"
  type        = string
}
