output "argocd_namespace" {
  description = "Kubernetes namespace ArgoCD is installed into"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart that was installed"
  value       = helm_release.argocd.version
}
