output "cloudfront_url" {
  description = "HTTPS URL of the CloudFront distribution — the public frontend URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "s3_bucket_name" {
  description = "S3 bucket name — used by CI to upload frontend files"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — used by CI for cache invalidation after deploy"
  value       = aws_cloudfront_distribution.main.id
}
