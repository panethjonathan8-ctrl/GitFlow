#!/bin/bash
# Records a deployment to the tracking file in S3.
# Called automatically by the deploy workflow after each successful deploy.
# Usage: ./scripts/track-deployment.sh <environment> <image_tag> <git_sha>

set -e

ENVIRONMENT=$1
IMAGE_TAG=$2
GIT_SHA=$3
REGION="eu-west-1"
BUCKET="gitflow-analyzer-tfstate-153772056450"
TRACKING_KEY="deployments/${ENVIRONMENT}/history.json"

if [ -z "$ENVIRONMENT" ] || [ -z "$IMAGE_TAG" ] || [ -z "$GIT_SHA" ]; then
  echo "Usage: $0 <environment> <image_tag> <git_sha>"
  exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Download existing history or start fresh
EXISTING=$(aws s3 cp "s3://$BUCKET/$TRACKING_KEY" - 2>/dev/null || echo "[]")

# Add new entry at the beginning of the array
# Keep only the last 20 deployments to prevent unbounded growth
NEW_ENTRY=$(cat << ENTRY
{
  "timestamp": "$TIMESTAMP",
  "environment": "$ENVIRONMENT",
  "image_tag": "$IMAGE_TAG",
  "git_sha": "$GIT_SHA",
  "deployed_by": "${GITHUB_ACTOR:-manual}"
}
ENTRY
)

# Use Python to safely manipulate the JSON
UPDATED=$(python3 << PYTHON
import json, sys

existing = json.loads('''$EXISTING''')
new_entry = json.loads('''$NEW_ENTRY''')

# Add new entry at the front
history = [new_entry] + existing

# Keep only last 20
history = history[:20]

print(json.dumps(history, indent=2))
PYTHON
)

# Upload updated history back to S3
echo "$UPDATED" | aws s3 cp - "s3://$BUCKET/$TRACKING_KEY" \
  --content-type "application/json" \
  --region "$REGION"

echo "Deployment recorded: $ENVIRONMENT / $IMAGE_TAG / $TIMESTAMP"
