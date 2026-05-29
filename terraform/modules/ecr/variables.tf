variable "project" {
  description = "Project name used as prefix on all resources"
  type        = string
}

variable "services" {
  description = "List of service names — one ECR repo will be created per service"
  type        = list(string)
  default     = ["analyzer", "graph-builder", "result-api"]
  # One repo per microservice.
  # Each service gets its own isolated repo so you can manage
  # permissions, lifecycle rules, and scanning independently.
  # For example later you could give a specific team access to
  # only one service's repo without touching the others.
}

variable "image_retention_count" {
  description = "How many images to keep per repo before older ones are deleted"
  type        = number
  default     = 10
  # In a capstone project you won't have hundreds of images
  # but this is good practice — without a lifecycle rule
  # images accumulate forever and storage costs grow silently.
  # 10 images = roughly 10 recent deploys worth of history.
}
