output "secret_arns" {
  description = "Map of secret name to ARN — attach these to your EC2 instance role"
  value = {
    for name, secret in aws_secretsmanager_secret.secrets :
    name => secret.arn
  }
}

output "read_secrets_policy_arn" {
  description = "ARN of the IAM policy that allows reading these secrets — attach to EC2 role"
  value       = aws_iam_policy.read_secrets.arn
}

output "secret_names" {
  description = "Full secret names including project/env prefix"
  value = {
    for name, secret in aws_secretsmanager_secret.secrets :
    name => secret.name
  }
}
