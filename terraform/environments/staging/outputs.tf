output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "github_actions_role_arn" {
  value = module.iam.github_actions_role_arn
}


output "secret_arns" {
  value = module.secrets.secret_arns
}

output "instance_id" {
  value = module.ec2.instance_id
}

output "api_url" {
  value = module.ec2.api_url
}

output "ssh_command" {
  value = module.ec2.ssh_command
}
