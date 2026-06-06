# ── Cluster IAM Role ──────────────────────────────────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "${var.project}-${var.env}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # The EKS service assumes this role to manage the control plane.
      # It uses these credentials to call EC2, ELB and other AWS APIs
      # when it creates load balancers or manages networking on your behalf.
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
  # AWS-managed policy with exactly what the EKS control plane needs.
  # Do not try to replicate it inline — the list is long and curated by AWS.
}

# ── Node Group IAM Role ───────────────────────────────────────────────────────
resource "aws_iam_role" "nodes" {
  name = "${var.project}-${var.env}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Nodes are EC2 instances. EC2 assumes this role so the kubelet and
      # VPC CNI plugin running on each node can make AWS API calls.
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
  # Allows kubelet on the node to register with the cluster API and
  # receive pod scheduling instructions.
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
  # The VPC CNI plugin (aws-node DaemonSet) runs on every node and allocates
  # VPC IP addresses directly to pods. Without this, pods cannot get a VPC IP
  # and all pod networking fails.
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
  # Allows nodes to pull images from ECR. Read-only — nodes cannot push.
  # This is coarse (any pod on any node can pull), which is fine for ECR.
  # Application-level AWS access (Secrets Manager) should use IRSA instead.
}

# ── Node Group IAM Policy: Secrets Manager ────────────────────────────────────
resource "aws_iam_role_policy" "node_secrets" {
  name = "secrets-manager-read"
  role = aws_iam_role.nodes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadProjectSecrets"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:*:*:secret:${var.project}/*"
      # Scoped to only secrets under your project prefix — same as the EC2 policy.
      # This gives all pods on all nodes Secrets Manager access, matching the
      # current EC2 behaviour. Once IRSA is set up (Week 4), this can be removed
      # and replaced with a pod-level role — but that is optional for this project.
    }]
  })
}

# ── Launch Template ───────────────────────────────────────────────────────────
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.project}-${var.env}-nodes-"
  # name_prefix lets AWS append a random suffix, avoiding naming collisions
  # when the template is replaced during updates.

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
      # Encrypted at rest — same principle as the EC2 module.
      # delete_on_termination prevents orphaned EBS volumes accumulating costs
      # after nodes are terminated.
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    # http_tokens = required enforces IMDSv2.
    # IMDSv2 requires a session token before the metadata service responds,
    # stopping SSRF attacks from silently stealing node credentials.
    # hop_limit must be 2 (not the default 1) because the request path is:
    #   pod → container network namespace → host → metadata service
    # At hop_limit = 1 pods cannot reach the metadata service at all, which
    # breaks IRSA credential injection.
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project}-${var.env}-node"
      Project     = var.project
      Environment = var.env
    }
  }

  lifecycle {
    create_before_destroy = true
    # Ensures a new template version exists before the old one is removed
    # during updates, so nodes can always launch.
  }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = "${var.project}-${var.env}"
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
    # endpoint_private_access = true: nodes talk to the API server over the
    # private VPC network — faster and stays inside AWS.
    # endpoint_public_access = true: you can also run kubectl from your laptop.
    # In a production setup, restrict public_access_cidrs to your office IPs.
    # For this capstone, 0.0.0.0/0 is acceptable.
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  # api: every API server request (who did what, when)
  # audit: all authenticated requests with their authorisation decisions
  # authenticator: all IAM-to-Kubernetes authentication attempts
  # Logs land in CloudWatch at /aws/eks/<cluster-name>/cluster.
  # scheduler and controllerManager are omitted — high-volume, rarely needed.

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
  # Cluster creation fails if the IAM role does not have its policy yet.
  # explicit depends_on ensures the attachment exists before EKS tries to use the role.

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── Managed Node Group ────────────────────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-${var.env}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types
  capacity_type   = var.capacity_type
  version         = var.cluster_version
  # Explicitly set so Terraform upgrades the node group whenever
  # cluster_version changes. Without this the nodes stay on the old
  # Kubernetes version and drift from the control plane.

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
    # Attaching the launch template gives nodes encrypted disks and IMDSv2.
    # Without it, nodes use the managed node group defaults: unencrypted,
    # IMDSv1 enabled, no custom tags.
  }

  scaling_config {
    min_size     = var.min_size
    max_size     = var.max_size
    desired_size = var.desired_size
  }

  update_config {
    max_unavailable = 1
    # During a node group update (new AMI, instance type change), at most
    # 1 node is replaced at a time. With desired_size = 2, one node is always
    # available to receive pods being drained from the replaced node.
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]
  # All three policies must be attached before the first node can register
  # with the cluster. If any policy is missing the node stays NotReady.

  tags = {
    Project     = var.project
    Environment = var.env
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
    # If you manually scale the node group (or the cluster autoscaler does it),
    # Terraform will want to reset desired_size on the next apply.
    # ignore_changes prevents that — min_size and max_size still apply.
  }
}

# ── OIDC Provider for IRSA ────────────────────────────────────────────────────
# IRSA (IAM Roles for Service Accounts) lets individual pods assume IAM roles.
# This OIDC provider is what makes that possible: it tells AWS to trust
# JWT tokens issued by this specific EKS cluster.
#
# Requires the hashicorp/tls provider. Add to the root module (environment):
#   terraform {
#     required_providers {
#       tls = { source = "hashicorp/tls", version = "~> 4.0" }
#     }
#   }
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
  # Fetches the TLS certificate of the EKS OIDC issuer endpoint.
  # The thumbprint below is derived from this certificate.
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  # Registers this cluster's OIDC endpoint with AWS IAM.
  # Once registered, IAM roles can include a condition like:
  #   StringEquals: "<issuer-url>:sub": "system:serviceaccount:<ns>:<sa-name>"
  # That condition means: only the pod using that Kubernetes service account
  # can assume this role — nothing else in the cluster.

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── EKS Add-ons ───────────────────────────────────────────────────────────────
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  # Assigns VPC IP addresses directly to pods. Required for IRSA to work
  # (pods need real VPC IPs for the metadata service hop to succeed).

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  # Provides in-cluster DNS. When result-api calls http://analyzer:5001,
  # CoreDNS resolves "analyzer" to the analyzer Service's ClusterIP.
  # Without CoreDNS, service-to-service calls by hostname do not work.

  depends_on = [aws_eks_node_group.main]
  # CoreDNS pods must schedule onto worker nodes.
  # Creating the addon before nodes exist leaves CoreDNS pods Pending.

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  # Maintains iptables rules on each node that implement Service routing.
  # Without it, traffic sent to a Service ClusterIP never reaches a pod.

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── GitHub Actions cluster access ─────────────────────────────────────────────
# EKS has two separate authorization layers:
#   1. IAM — controls who can call AWS APIs (create clusters, node groups, etc.)
#   2. Kubernetes RBAC — controls who can call the Kubernetes API (list pods, etc.)
#
# The GitHub Actions role already has IAM permissions via its attached policies.
# These two resources grant it Kubernetes API access so that terraform plan/apply
# can read and write Helm releases and Kubernetes resources from CI.
#
# Security note: we use OIDC so the role can only be assumed by workflows
# running from your specific GitHub repo — not by arbitrary callers.
# AmazonEKSClusterAdminPolicy is broad but acceptable for a dev environment.
# In production, scope this down to a custom ClusterRole with only the
# get/list/watch permissions needed for plan and create/update/delete for apply.

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.github_actions_role_arn
  type          = "STANDARD"

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.github_actions_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}
