output "namespace" {
  description = "Kubernetes namespace where Prometheus and Grafana are installed"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "grafana_service_name" {
  description = "Kubernetes service name for Grafana — use with kubectl port-forward to access the UI"
  value       = "monitoring-grafana"
}

output "grafana_url" {
  description = "Public URL for Grafana"
  value       = "https://${var.grafana_hostname}"
}

output "grafana_cloudfront_domain" {
  description = "CloudFront domain for Grafana — add this as a CNAME for grafana.gitflow.space in GoDaddy"
  value       = aws_cloudfront_distribution.grafana.domain_name
}

output "grafana_acm_validation_record" {
  description = "DNS CNAME record to add to GoDaddy to validate the Grafana ACM certificate"
  value = {
    name  = tolist(aws_acm_certificate.grafana.domain_validation_options)[0].resource_record_name
    value = tolist(aws_acm_certificate.grafana.domain_validation_options)[0].resource_record_value
    type  = "CNAME"
  }
}
