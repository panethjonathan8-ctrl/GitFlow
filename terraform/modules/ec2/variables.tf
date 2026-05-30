variable "project" {
  description = "Project name used as prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to launch the instance into"
  type        = string
  # Passed in from the VPC module output.
  # The EC2 module does not create its own VPC — it uses the one you built.
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance into"
  type        = string
  # You will use the first public subnet from the VPC module.
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
  # t3.micro is free tier eligible for the first 750 hours per month.
  # For a capstone project this is plenty — 1 vCPU, 1GB RAM.
  # When you move to Phase 2 you can change this to t3.small or t3.medium
  # without touching any other part of the config.
}

variable "ecr_registry" {
  description = "ECR registry URL — account_id.dkr.ecr.region.amazonaws.com"
  type        = string
  # Used in the user data script to authenticate Docker to ECR.
}

variable "ecr_repo" {
  description = "Full ECR repository URL for the analyzer image"
  type        = string
  # Used in the user data script to pull the correct image.
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach port 5000 — restrict this in production"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  # 0.0.0.0/0 means anyone on the internet can reach port 5000.
  # This is fine for a capstone project where you want to test the API.
  # In production you would restrict this to your office IP or put an
  # ALB in front and only allow traffic from the ALB.
}
