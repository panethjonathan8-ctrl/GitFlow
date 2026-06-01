output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Fixed public IP — does not change on stop/start"
  value       = aws_eip.app.public_ip
}

output "public_dns" {
  description = "Public DNS name"
  value       = aws_instance.app.public_dns
}

output "api_url" {
  description = "Full URL to reach the API"
  value       = "http://${aws_eip.app.public_ip}:5000"
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = "ssh -i ~/.ssh/gitflow-analyzer-dev ec2-user@${aws_eip.app.public_ip}"
}
