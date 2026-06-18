variable "project" {
  description = "Project name used as a prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name — dev, staging, or production"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to place the RDS instance in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group — must span at least two AZs"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS nodes — only this SG gets port 5432 access"
  type        = string
}

variable "db_name" {
  description = "Name of the initial database to create inside the PostgreSQL instance"
  type        = string
  default     = "gitflow"
}

variable "db_username" {
  description = "Master username for the PostgreSQL instance"
  type        = string
  default     = "gitflow"
}
