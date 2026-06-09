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
  # Pin to an explicit version so upgrades are deliberate, not accidental.
  # Check https://github.com/prometheus-community/helm-charts/releases for updates.
}
