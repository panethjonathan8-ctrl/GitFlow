output "endpoint" {
  description = "RDS instance endpoint (hostname only, no port) — pass this to the app as DB_HOST"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "Port the RDS instance listens on"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the database inside the PostgreSQL instance"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Master username"
  value       = aws_db_instance.main.username
}

output "password_secret_name" {
  description = "Secrets Manager secret name containing the DB password"
  value       = aws_secretsmanager_secret.db_password.name
}

output "rds_security_group_id" {
  description = "ID of the RDS security group — used by the EKS-to-RDS ingress rule in main.tf"
  value       = aws_security_group.rds.id
}
