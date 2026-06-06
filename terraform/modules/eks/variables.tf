variable "project" {
  description = "Project name used as a prefix on all resources"
  type        = string
}

variable "env" {
  description = "Environment name — dev, staging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster lives"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for nodes and the control plane. Must span at least two AZs."
  type        = list(string)
  # Pass module.vpc.public_subnet_ids from the environment.
  # The VPC module already tags these subnets with kubernetes.io/role/elb = 1
  # so EKS can find them automatically for load balancer provisioning.
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
  # Pinned so you control upgrades — EKS will not auto-upgrade.
  # Each version has a ~14-month standard support window.
  # Check https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  # when it is time to upgrade.
}

variable "instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.small"]
  # t3.small = 2 vCPU, 2 GB RAM.
  # Each node needs ~300 MB for Kubernetes system pods (kube-proxy, vpc-cni,
  # coredns). That leaves ~1.7 GB for your application pods.
  # Three microservices at ~256 MB each = ~768 MB. Two nodes is comfortable.
  # Upgrade to t3.medium (4 GB) if pods OOMKill in practice.
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is ~70% cheaper but nodes can be interrupted."
  type        = string
  default     = "ON_DEMAND"
  # Kubernetes handles SPOT interruptions gracefully (2-min notice, pods
  # reschedule to other nodes) — but only if another node exists to land on.
  # ON_DEMAND is simpler to reason about for initial setup.
  # To cut node costs by ~70%: change this to "SPOT".
}

variable "min_size" {
  description = "Minimum number of nodes in the group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes the autoscaler can scale to"
  type        = number
  default     = 3
}

variable "desired_size" {
  description = "Initial node count at launch"
  type        = number
  default     = 2
  # Two nodes so rolling updates work without downtime:
  # one node drains, pods reschedule to the other.
  # Scale down to 1 when not actively testing to save ~$0.023/hr.
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size in GB for each worker node"
  type        = number
  default     = 20
  # 20 GB covers the node OS, kubelet, and your three service images
  # (~200 MB each). This is the EKS-recommended minimum.
}

variable "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role — granted read/write access to the cluster so terraform plan and apply work in CI"
  type        = string
}
