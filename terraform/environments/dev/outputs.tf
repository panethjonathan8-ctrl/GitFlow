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

output "api_url" {
  description = "URL to reach the API"
  value       = module.ec2.api_url
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = module.ec2.ssh_command
}
