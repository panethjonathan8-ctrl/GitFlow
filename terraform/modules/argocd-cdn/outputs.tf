output "argocd_cloudfront_domain" {
  description = "CloudFront domain for ArgoCD — add this as a CNAME for argocd.gitflow.space in GoDaddy"
  value       = aws_cloudfront_distribution.argocd.domain_name
}

output "argocd_acm_validation_record" {
  description = "DNS CNAME record to add to GoDaddy to validate the ArgoCD ACM certificate"
  value = {
    name  = tolist(aws_acm_certificate.argocd.domain_validation_options)[0].resource_record_name
    value = tolist(aws_acm_certificate.argocd.domain_validation_options)[0].resource_record_value
    type  = "CNAME"
  }
}
