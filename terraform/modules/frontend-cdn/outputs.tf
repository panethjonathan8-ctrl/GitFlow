output "cloudfront_url" {
  description = "HTTPS URL of the CloudFront distribution — the public frontend URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "acm_validation_records" {
  description = "CNAME records to add in GoDaddy to validate the ACM certificate — add these while terraform apply is running"
  value = {
    for dvo in aws_acm_certificate.cdn.domain_validation_options : dvo.domain_name => {
      cname_name  = dvo.resource_record_name
      cname_value = dvo.resource_record_value
    }
  }
}

output "s3_bucket_name" {
  description = "S3 bucket name — used by CI to upload frontend files"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — used by CI for cache invalidation after deploy"
  value       = aws_cloudfront_distribution.main.id
}
