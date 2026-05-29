variable "project" {
  description = "Project name used as prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "secret_names" {
  description = "List of secret names to create — values are set manually after apply"
  type        = list(string)
  default     = ["github-token"]
  # You define the secret containers here in Terraform.
  # The actual secret VALUES are set manually via CLI after apply.
  # This separation is intentional — values never touch Terraform state or git.
}
