output "repository_urls" {
  description = "Map of service name to ECR repository URL — used in CI to know where to push images"
  value = {
    for service, repo in aws_ecr_repository.services :
    service => repo.repository_url
  }
  # Output looks like:
  # {
  #   "analyzer"      = "153772056450.dkr.ecr.eu-west-1.amazonaws.com/gitflow-analyzer/analyzer"
  #   "graph-builder" = "153772056450.dkr.ecr.eu-west-1.amazonaws.com/gitflow-analyzer/graph-builder"
  #   "result-api"    = "153772056450.dkr.ecr.eu-west-1.amazonaws.com/gitflow-analyzer/result-api"
  # }
  # Your CI pipeline uses these URLs to tag and push images.
}

output "repository_arns" {
  description = "Map of service name to ECR repository ARN — used in IAM policies"
  value = {
    for service, repo in aws_ecr_repository.services :
    service => repo.arn
  }
}

output "registry_id" {
  description = "The registry ID — same as your AWS account ID"
  value       = values(aws_ecr_repository.services)[0].registry_id
}
