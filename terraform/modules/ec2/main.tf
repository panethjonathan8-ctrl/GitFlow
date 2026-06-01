# ── Look up the latest Amazon Linux 2023 AMI ─────────────────────────────────
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  # Always use the latest official Amazon Linux 2023 AMI.
  # Hardcoding an AMI ID is dangerous — AMIs are region-specific and
  # the one you hardcode may be deprecated or removed.
  # This data source always finds the latest one automatically.

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
    # al2023 = Amazon Linux 2023
    # x86_64 = standard Intel/AMD architecture matching t3.micro
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── IAM role for the EC2 instance ─────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.project}-${var.env}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # This allows the EC2 service to assume this role.
      # The instance automatically gets credentials from this role
      # via the instance metadata service — no keys needed anywhere.
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ── Policy: allow EC2 to pull from ECR ────────────────────────────────────────
resource "aws_iam_role_policy" "ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
        # GetAuthorizationToken must be * — it operates at registry level
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.project}/*"
        # Scoped to only your project's repos — not every ECR repo in the account
      }
    ]
  })
}

# ── Policy: allow EC2 to read secrets ────────────────────────────────────────
resource "aws_iam_role_policy" "secrets" {
  name = "read-secrets"
  role = aws_iam_role.ec2.id

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
      # Scoped to only secrets prefixed with your project name
    }]
  })
}

# ── Policy: allow SSM agent to communicate with AWS ───────────────────────────
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  # This AWS managed policy gives the instance everything it needs
  # to communicate with the SSM service.
  # Without this the SSM agent on the instance cannot register itself
  # and remote commands will never arrive.
}

# ── Instance profile ───────────────────────────────────────────────────────────
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.env}-ec2-profile"
  role = aws_iam_role.ec2.name
  # An instance profile is a container for an IAM role that EC2 can use.
  # You cannot attach a role directly to an EC2 instance —
  # it must be wrapped in an instance profile first.
}

# ── Security group ────────────────────────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.env}-ec2-sg"
  description = "Security group for ${var.project} EC2 instance"
  vpc_id      = var.vpc_id

  # Allow inbound HTTP traffic on port 5000 — your Flask app
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Flask API"
  }

  # Allow inbound SSH on port 22 — for debugging only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH access"
    # In production you would restrict this to your IP only.
    # For a capstone project 0.0.0.0/0 is acceptable but be aware
    # that bots scan for open SSH ports constantly.
    # Use SSH key authentication — never password authentication.
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
    # -1 protocol means all protocols.
    # Outbound must be open so the instance can:
    # - Pull Docker images from ECR
    # - Clone repos from GitHub
    # - Call AWS APIs (Secrets Manager, ECR)
  }

  tags = {
    Name        = "${var.project}-${var.env}-ec2-sg"
    Project     = var.project
    Environment = var.env
  }
}

# ── SSH key pair ───────────────────────────────────────────────────────────────
resource "aws_key_pair" "ec2" {
  key_name   = "${var.project}-${var.env}-key"
  public_key = var.ec2_public_key
  # Key content passed in as a variable instead of read from a file.
  # This works both locally and in CI.
}
# ── EC2 instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  key_name               = aws_key_pair.ec2.key_name

  associate_public_ip_address = true
  # Gives the instance a public IP so you can reach it from the internet.
  # In Phase 2 with a load balancer, only the ALB would be public
  # and the instance would be in a private subnet.

  user_data = templatefile("${path.module}/user_data.sh", {
    aws_region   = var.aws_region
    ecr_registry = var.ecr_registry
    ecr_repo     = var.ecr_repo
    project      = var.project
    env          = var.env
  })
  # templatefile reads user_data.sh and replaces ${aws_region},
  # ${ecr_registry} etc with the actual values at plan time.
  # This is how you pass Terraform variables into a shell script.

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
    # 20GB encrypted root volume.
    # gp3 is the latest generation SSD — faster and cheaper than gp2.
    # Encryption at rest means even if someone steals the physical disk
    # they cannot read your data.
  }

  tags = {
    Name        = "${var.project}-${var.env}-app"
    Project     = var.project
    Environment = var.env
  }

  lifecycle {
    # If the AMI changes (new Amazon Linux release), Terraform will want
    # to replace the instance. ignore_changes prevents this —
    # you control when to replace the instance manually.
    ignore_changes = [ami, user_data]
  }
}
