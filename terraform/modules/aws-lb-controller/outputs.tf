output "role_arn" {
  description = "ARN of the IAM role the LB controller assumes via IRSA"
  value       = aws_iam_role.lb_controller.arn
}

output "role_name" {
  description = "Name of the LB controller IAM role"
  value       = aws_iam_role.lb_controller.name
}
