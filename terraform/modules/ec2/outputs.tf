output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP address — use this to reach the API"
  value       = aws_instance.app.public_ip
}

output "public_dns" {
  description = "Public DNS name of the instance"
  value       = aws_instance.app.public_dns
}

output "api_url" {
  description = "Full URL to reach the API"
  value       = "http://${aws_instance.app.public_ip}:5000"
}

output "ssh_command" {
  description = "Copy-paste command to SSH into the instance"
  value       = "ssh -i ~/.ssh/gitflow-analyzer-dev ec2-user@${aws_instance.app.public_ip}"
}
