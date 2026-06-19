output "tfstate_bucket_name" {
  description = "Paste this into the backend block of all other Terraform modules"
  value       = aws_s3_bucket.tfstate.bucket
}

output "tflock_table_name" {
  description = "Paste this into the backend block of all other Terraform modules"
  value       = aws_dynamodb_table.tflock.name
}

output "aws_region" {
  description = "Region everything was created in"
  value       = var.aws_region
}
