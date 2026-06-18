output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "github_actions_role_arn" {
  description = "Paste this into your GitHub Actions workflow"
  value       = module.iam.github_actions_role_arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for all services"
  value       = module.ecr.repository_urls
}

output "secret_arns" {
  description = "Secret ARNs"
  value       = module.secrets.secret_arns
}

output "irsa_role_arn" {
  description = "IRSA role ARN — add this to values-dev.yaml under serviceAccount.annotations"
  value       = module.irsa.role_arn
}

output "eks_cluster_name" {
  description = "EKS cluster name — used in aws eks update-kubeconfig"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN — needed for IRSA (pod-level IAM roles)"
  value       = module.eks.oidc_provider_arn
}

output "cloudfront_url" {
  description = "Frontend URL — open this in your browser"
  value       = module.frontend_cdn.cloudfront_url
}

output "frontend_bucket" {
  description = "S3 bucket name — set as FRONTEND_BUCKET in GitHub Actions variables"
  value       = module.frontend_cdn.s3_bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — set as CLOUDFRONT_DISTRIBUTION_ID in GitHub Actions variables"
  value       = module.frontend_cdn.cloudfront_distribution_id
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint — copy this into values-dev.yaml and values-production.yaml under resultApi.database.host"
  value       = module.rds.endpoint
}

output "rds_password_secret" {
  description = "Secrets Manager secret name holding the DB password"
  value       = module.rds.password_secret_name
}
