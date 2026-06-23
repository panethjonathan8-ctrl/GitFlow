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

variable "github_username" {
  description = "GitHub username — used to build the repo URL for the ArgoCD Application"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name — the repo ArgoCD watches for Helm chart changes"
  type        = string
  default     = "GitFlow"
}

variable "aws_region" {
  description = "AWS region — used to configure kubectl after the cluster is created"
  type        = string
}

variable "argocd_hostname" {
  description = "Public hostname for the ArgoCD UI — must match the CloudFront alias and GoDaddy CNAME"
  type        = string
  default     = "argocd.gitflow.space"
}

variable "argocd_github_oauth_client_id" {
  description = "GitHub OAuth App client ID — create the app at github.com/settings/developers, callback URL must be https://argocd.gitflow.space/api/dex/callback"
  type        = string
}

variable "argocd_github_oauth_client_secret" {
  description = "GitHub OAuth App client secret — store in terraform.tfvars only, never commit this value"
  type        = string
  sensitive   = true
}

variable "argocd_github_allowed_user" {
  description = "GitHub username that is allowed to log into ArgoCD — all other accounts are rejected"
  type        = string
}
