variable "project" {
  description = "Project name used as a prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name — dev, staging, or prod"
  type        = string
}

variable "vpc_cidr" {
  description = "The IP range for the entire VPC"
  type        = string
  default     = "10.0.0.0/16"
  # /16 gives you 65,536 addresses.
  # Public subnets will use a small slice of this.
  # The rest is reserved for private subnets in Phase 2.
}

variable "public_subnet_cidrs" {
  description = "IP ranges for the public subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  # /24 gives each subnet 256 addresses — more than enough for Phase 1.
  # Two subnets across two AZs because a Load Balancer requires at least 2 AZs.
  # You only use one now but the second costs nothing until something is in it.
}

variable "private_subnet_cidrs" {
  description = "IP ranges for the private subnets, one per availability zone. Used for RDS and any future private resources."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  # These CIDRs sit inside the 10.0.0.0/16 VPC range but do not overlap with
  # the public subnets (10.0.1.0/24, 10.0.2.0/24).
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}
