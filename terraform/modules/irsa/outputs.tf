output "role_arn" {
  description = "ARN of the IRSA role — add this to the ServiceAccount annotation in values-dev.yaml under serviceAccount.annotations"
  value       = aws_iam_role.app.arn
}

output "role_name" {
  description = "Name of the IRSA IAM role"
  value       = aws_iam_role.app.name
}
