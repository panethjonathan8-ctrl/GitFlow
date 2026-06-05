variable "project" {
  description = "Project name — used for tagging and naming resources"
  type        = string
}

variable "env" {
  description = "Environment name (dev, staging) — used for tagging and naming resources"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster ArgoCD will be installed into"
  type        = string
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart — pin this to avoid unexpected upgrades"
  type        = string
  default     = "7.7.16"
  # ArgoCD chart 7.7.16 = ArgoCD app version v2.13.4
  # Check for newer versions at: https://artifacthub.io/packages/helm/argo/argo-cd
}
