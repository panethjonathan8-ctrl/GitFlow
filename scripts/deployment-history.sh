#!/bin/bash
# Shows deployment history for an environment.
# Usage: ./scripts/deployment-history.sh [environment]
# Default environment is dev.

ENVIRONMENT=${1:-dev}
REGION="eu-west-1"
BUCKET="gitflow-analyzer-tfstate-153772056450"
TRACKING_KEY="deployments/${ENVIRONMENT}/history.json"

echo "=== Deployment history for: $ENVIRONMENT ==="
echo ""

# Download and display history
HISTORY=$(aws s3 cp "s3://$BUCKET/$TRACKING_KEY" - 2>/dev/null)

if [ -z "$HISTORY" ]; then
  echo "No deployment history found for $ENVIRONMENT"
  echo "History is recorded automatically after each deployment"
  exit 0
fi

# Format and display using Python
python3 << PYTHON
import json

history = json.loads('''$HISTORY''')

if not history:
  print("No deployments recorded yet")
else:
  print(f"{'#':<4} {'Timestamp':<22} {'Image Tag':<12} {'Git SHA':<10} {'Deployed By'}")
  print("-" * 70)
  for i, entry in enumerate(history):
    tag = entry.get('image_tag', 'unknown')
    sha = entry.get('git_sha', 'unknown')[:7]
    ts  = entry.get('timestamp', 'unknown')
    by  = entry.get('deployed_by', 'unknown')
    marker = " <- current" if i == 0 else ""
    print(f"{i:<4} {ts:<22} {tag:<12} {sha:<10} {by}{marker}")

print("")
print(f"Total deployments recorded: {len(history)}")
PYTHON
