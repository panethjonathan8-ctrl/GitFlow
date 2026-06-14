variable "project" {
  description = "Project name used as a prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name — dev, staging"
  type        = string
}

variable "grafana_admin_password" {
  description = "Password for the Grafana admin user — set this in terraform.tfvars, never hardcode it"
  type        = string
  sensitive   = true
}

variable "prometheus_retention" {
  description = "How long Prometheus keeps metrics before deleting them"
  type        = string
  default     = "15d"
  # 15 days is the Prometheus default and sufficient for a dev environment.
  # Increase to 30d or more in staging/production if you need longer history.
}

variable "prometheus_storage_size" {
  description = "Size of the EBS volume for Prometheus metric storage"
  type        = string
  default     = "10Gi"
  # 10Gi is enough for a dev cluster with a handful of services and 15-day retention.
  # A rough rule: each target scraped every 15s generates ~1MB/day.
  # At 15 targets × 1MB × 15 days = ~225MB. 10Gi gives plenty of headroom.
}

variable "chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart to install"
  type        = string
  default     = "67.5.0"
}

variable "loki_chart_version" {
  description = "Version of the Loki Helm chart"
  type        = string
  default     = "6.7.4"
  # Loki 6.x = Loki app version 3.x (single binary mode).
  # Check https://github.com/grafana/loki/releases for updates.
}

variable "tempo_chart_version" {
  description = "Version of the Tempo Helm chart"
  type        = string
  default     = "1.10.3"
  # Check https://github.com/grafana/helm-charts/releases for updates.
}

variable "loki_storage_size" {
  description = "Size of the EBS volume for Loki log storage"
  type        = string
  default     = "10Gi"
}

variable "tempo_storage_size" {
  description = "Size of the EBS volume for Tempo trace storage"
  type        = string
  default     = "10Gi"
}

variable "alloy_chart_version" {
  description = "Version of the Grafana Alloy Helm chart"
  type        = string
  default     = "0.9.2"
  # Alloy replaces Grafana Agent. Check https://github.com/grafana/alloy/releases.
}

variable "github_oauth_client_id" {
  description = "GitHub OAuth App client ID — create the app at github.com/settings/developers, callback URL must be https://grafana.gitflow.space/login/github"
  type        = string
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth App client secret — store in terraform.tfvars only, never commit this value"
  type        = string
  sensitive   = true
}

variable "github_oauth_allowed_user" {
  description = "GitHub username that is allowed to log into Grafana — only this user can authenticate via OAuth"
  type        = string
}

variable "grafana_hostname" {
  description = "Public hostname for Grafana — must match the CloudFront alias and GoDaddy CNAME record"
  type        = string
  default     = "grafana.gitflow.space"
}

variable "alb_dns_name" {
  description = "DNS name of the shared ALB — used as the CloudFront origin for the Grafana distribution"
  type        = string
}
