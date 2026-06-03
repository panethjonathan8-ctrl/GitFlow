#!/bin/bash
# Rolls back an environment to a specific image version.
# Usage: ./scripts/rollback.sh <environment> [image_tag]
#
# Examples:
#   ./scripts/rollback.sh dev              <- rolls back to previous version
#   ./scripts/rollback.sh dev abc1234      <- rolls back to specific SHA
#   ./scripts/rollback.sh staging def5678  <- rolls back staging to specific SHA

set -e

ENVIRONMENT=${1:-dev}
SPECIFIC_TAG=$2
REGION="eu-west-1"
BUCKET="gitflow-analyzer-tfstate-153772056450"
ECR_REGISTRY="153772056450.dkr.ecr.eu-west-1.amazonaws.com"
TRACKING_KEY="deployments/${ENVIRONMENT}/history.json"

echo "=== GitFlow Analyzer Rollback ==="
echo "Environment: $ENVIRONMENT"
echo ""

# ── Get the instance ID for the target environment ────────────────────────────
if [ "$ENVIRONMENT" = "dev" ]; then
  INSTANCE_ID=$(cd ~/GitFlow/terraform/environments/dev && terraform output -raw instance_id)
  API_URL=$(cd ~/GitFlow/terraform/environments/dev && terraform output -raw api_url)
elif [ "$ENVIRONMENT" = "staging" ]; then
  INSTANCE_ID=$(cd ~/GitFlow/terraform/environments/staging && terraform output -raw instance_id)
  API_URL=$(cd ~/GitFlow/terraform/environments/staging && terraform output -raw api_url)
else
  echo "ERROR: Unknown environment '$ENVIRONMENT'. Use 'dev' or 'staging'"
  exit 1
fi

echo "Instance: $INSTANCE_ID"
echo "API URL:  $API_URL"
echo ""

# ── Determine which image tag to roll back to ─────────────────────────────────
if [ -n "$SPECIFIC_TAG" ]; then
  ROLLBACK_TAG="$SPECIFIC_TAG"
  echo "Rolling back to specified tag: $ROLLBACK_TAG"
else
  echo "No tag specified — finding previous deployment..."

  HISTORY=$(aws s3 cp "s3://$BUCKET/$TRACKING_KEY" - 2>/dev/null || echo "[]")

  ROLLBACK_TAG=$(python3 << PYTHON
import json

history = json.loads('''$HISTORY''')

if len(history) < 2:
  print("NONE")
else:
  print(history[1].get('image_tag', 'NONE'))
PYTHON
)

  if [ "$ROLLBACK_TAG" = "NONE" ]; then
    echo "ERROR: No previous deployment found in history"
    echo "Run ./scripts/deployment-history.sh $ENVIRONMENT to see available versions"
    echo "Then run: ./scripts/rollback.sh $ENVIRONMENT <specific_tag>"
    exit 1
  fi

  echo "Rolling back to previous deployment: $ROLLBACK_TAG"
fi

# ── Verify all three images exist in ECR ─────────────────────────────────────
echo ""
echo "Verifying images exist in ECR..."
for REPO in gitflow-analyzer/analyzer gitflow-analyzer/graph-builder gitflow-analyzer/result-api; do
  STATUS=$(aws ecr describe-images \
    --repository-name "$REPO" \
    --image-ids imageTag="$ROLLBACK_TAG" \
    --region "$REGION" \
    --query "imageDetails[0].imageTags[0]" \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "$STATUS" = "NOT_FOUND" ] || [ "$STATUS" = "None" ]; then
    echo "ERROR: Tag '$ROLLBACK_TAG' not found in ECR repo '$REPO'"
    exit 1
  fi
  echo "Verified: $REPO:$ROLLBACK_TAG"
done

# ── Check SSM connectivity ────────────────────────────────────────────────────
echo ""
echo "Checking SSM connectivity..."
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region "$REGION" \
  --query "InstanceInformationList[0].PingStatus" \
  --output text)

if [ "$SSM_STATUS" != "Online" ]; then
  echo "ERROR: Instance not reachable via SSM (status: $SSM_STATUS)"
  exit 1
fi
echo "SSM status: Online"
echo ""

# ── Deploy the rollback ───────────────────────────────────────────────────────
echo "Deploying rollback to: $ROLLBACK_TAG"
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    \"set -e\",
    \"echo === Rolling back $ENVIRONMENT to $ROLLBACK_TAG ===\",
    \"docker stop analyzer graph-builder result-api 2>/dev/null || true\",
    \"docker rm analyzer graph-builder result-api 2>/dev/null || true\",
    \"docker network create gitflow-net 2>/dev/null || true\",
    \"aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY\",
    \"docker pull $ECR_REGISTRY/gitflow-analyzer/analyzer:$ROLLBACK_TAG\",
    \"docker pull $ECR_REGISTRY/gitflow-analyzer/graph-builder:$ROLLBACK_TAG\",
    \"docker pull $ECR_REGISTRY/gitflow-analyzer/result-api:$ROLLBACK_TAG\",
    \"docker run -d --name analyzer --network gitflow-net -p 5001:5001 -e PORT=5001 -e AWS_REGION=$REGION -e PROJECT_NAME=gitflow-analyzer -e ENVIRONMENT=$ENVIRONMENT -e GIT_PYTHON_REFRESH=quiet --restart unless-stopped --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 $ECR_REGISTRY/gitflow-analyzer/analyzer:$ROLLBACK_TAG\",
    \"docker run -d --name graph-builder --network gitflow-net -p 5002:5002 -e PORT=5002 -e AWS_REGION=$REGION -e PROJECT_NAME=gitflow-analyzer -e ENVIRONMENT=$ENVIRONMENT -e GIT_PYTHON_REFRESH=quiet --restart unless-stopped --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 $ECR_REGISTRY/gitflow-analyzer/graph-builder:$ROLLBACK_TAG\",
    \"docker run -d --name result-api --network gitflow-net -p 5000:5000 -e PORT=5000 -e ANALYZER_URL=http://analyzer:5001 -e GRAPH_BUILDER_URL=http://graph-builder:5002 --restart unless-stopped --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 $ECR_REGISTRY/gitflow-analyzer/result-api:$ROLLBACK_TAG\",
    \"echo === Rollback complete ===\",
    \"docker ps\"
  ]" \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text)

echo "Command ID: $COMMAND_ID"
echo "Waiting for rollback to complete..."

aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"

echo ""
echo "=== Rollback output ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" \
  --output text

# ── Health check ──────────────────────────────────────────────────────────────
echo ""
echo "=== Health check ==="
sleep 10
for i in 1 2 3; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/health")
  if [ "$STATUS" = "200" ]; then
    echo "Health check passed"
    echo ""
    echo "=== Rollback successful ==="
    echo "Environment: $ENVIRONMENT"
    echo "Rolled back to: $ROLLBACK_TAG"
    echo "API URL: $API_URL"

    python3 ~/GitFlow/scripts/record-deployment.py \
      "$ENVIRONMENT" \
      "$ROLLBACK_TAG" \
      "$ROLLBACK_TAG" \
      "$(git config user.name 2>/dev/null || echo 'manual')" \
      "$REGION"

    exit 0
  fi
  echo "Attempt $i: got $STATUS — retrying in 10s"
  sleep 10
done

echo "ERROR: Health check failed after rollback"
exit 1
