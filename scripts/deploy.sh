#!/bin/bash
# Manual deploy script
# Usage: ./scripts/deploy.sh
# Triggers a redeploy of the latest image on EC2

set -e

REGION="eu-west-1"

echo "=== GitFlow Analyzer Manual Deploy ==="

# Get values from Terraform
cd "$(dirname "$0")/../terraform/environments/dev"
INSTANCE_ID=$(terraform output -raw instance_id)
API_URL=$(terraform output -raw api_url)
cd - > /dev/null

echo "Instance: $INSTANCE_ID"
echo "API URL:  $API_URL"
echo ""

# Check the instance is reachable via SSM
echo "Checking SSM connectivity..."
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region "$REGION" \
  --query "InstanceInformationList[0].PingStatus" \
  --output text)

if [ "$SSM_STATUS" != "Online" ]; then
  echo "ERROR: Instance is not reachable via SSM (status: $SSM_STATUS)"
  echo "Make sure the instance is running and SSM agent is active"
  exit 1
fi

echo "SSM status: Online"
echo ""

# Send deploy command to the instance
echo "Sending deploy command..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo === Starting deploy ===",
    "cd /opt/gitflow-analyzer",
    "aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 153772056450.dkr.ecr.eu-west-1.amazonaws.com",
    "docker-compose pull",
    "docker-compose up -d",
    "echo === Deploy complete ===",
    "docker ps"
  ]' \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text)

echo "Command ID: $COMMAND_ID"
echo "Waiting for deploy to complete..."

# Wait for the command to finish
aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"

# Show the output from the instance
echo ""
echo "=== Deploy output ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" \
  --output text

# Health check — try 3 times
echo ""
echo "=== Health check ==="
sleep 10
for i in 1 2 3; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/health")
  if [ "$STATUS" = "200" ]; then
    echo "Health check passed"
    echo ""
    echo "=== Deployment successful ==="
    echo "API URL: $API_URL"
    exit 0
  fi
  echo "Attempt $i: got $STATUS — retrying in 10s"
  sleep 10
done

echo "ERROR: Health check failed after 3 attempts"
exit 1
