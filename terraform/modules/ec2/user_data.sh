#!/bin/bash
# This script runs once on first boot as root.
# Output is logged to /var/log/user-data.log so you can debug issues.
exec > /var/log/user-data.log 2>&1
set -e
# set -e means the script stops immediately if any command fails.
# Without this, a failed step would be silently skipped.

echo "=== Starting user data script ==="
echo "Timestamp: $(date)"

# ── Install Docker ────────────────────────────────────────────────────────────
echo "=== Installing Docker ==="
dnf update -y
dnf install -y docker git

# Start Docker and enable it to start automatically on reboot
systemctl start docker
systemctl enable docker

# Add ec2-user to the docker group so it can run docker without sudo
usermod -aG docker ec2-user

echo "=== Docker installed ==="
docker --version

# ── Install Docker Compose ────────────────────────────────────────────────────
echo "=== Installing Docker Compose ==="
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version

# ── Authenticate Docker to ECR ────────────────────────────────────────────────
echo "=== Authenticating to ECR ==="
# The EC2 instance uses its IAM role to get ECR credentials.
# No access keys needed — the role gives permission automatically.
aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS \
  --password-stdin ${ecr_registry}

echo "=== ECR login successful ==="

# ── Create app directory ──────────────────────────────────────────────────────
mkdir -p /opt/gitflow-analyzer
cd /opt/gitflow-analyzer

# ── Write docker-compose.yml ──────────────────────────────────────────────────
echo "=== Writing docker-compose.yml ==="
cat > docker-compose.yml << 'COMPOSE'
version: "3.9"
services:
  app:
    image: ${ecr_repo}:latest
    container_name: gitflow-analyzer-app
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=production
      - PORT=5000
      - AWS_REGION=${aws_region}
      - PROJECT_NAME=${project}
      - ENVIRONMENT=${env}
      - GIT_PYTHON_REFRESH=quiet
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE

# ── Pull the latest image ─────────────────────────────────────────────────────
echo "=== Pulling image from ECR ==="
docker-compose pull

# ── Start the application ─────────────────────────────────────────────────────
echo "=== Starting application ==="
docker-compose up -d
# -d means detached — runs in the background

echo "=== Waiting for app to be healthy ==="
sleep 15

# Check the app is responding
curl -f http://localhost:5000/health && \
  echo "=== App is healthy ===" || \
  echo "=== WARNING: Health check failed — check docker logs ==="

echo "=== User data script complete ==="
echo "Timestamp: $(date)"
