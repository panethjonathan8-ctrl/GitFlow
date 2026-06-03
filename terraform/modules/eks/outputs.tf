output "cluster_name" {
  description = "Name of the EKS cluster — used in kubeconfig and kubectl commands"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "API server HTTPS endpoint — used in kubeconfig and CI/CD pipelines"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate — used in kubeconfig"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL — used when building IRSA trust policies"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider — used as the Federated principal in IRSA role trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_role_arn" {
  description = "ARN of the IAM role attached to worker nodes"
  value       = aws_iam_role.nodes.arn
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = aws_eks_node_group.main.node_group_name
}
