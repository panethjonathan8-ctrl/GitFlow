#!/bin/bash
# Smoke-tests a deployed environment by port-forwarding to result-api.
# Usage: scripts/smoke-test.sh <namespace>
# Example: scripts/smoke-test.sh gitflow-analyzer-dev
#
# Checks:
#   /health  — must return HTTP 200
#   /analyze — must return JSON with status=success
set -e

NAMESPACE="${1:?Usage: $0 <namespace>}"
LOCAL_PORT=18080

echo "=== Smoke test: $NAMESPACE ==="

# Wait for all three deployments to finish rolling out before port-forwarding.
# kubectl rollout status blocks until every pod in the deployment is Ready.
# Timeout 300s — if pods haven't started in 5 minutes something is wrong.
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/analyzer --namespace "$NAMESPACE" --timeout=300s
kubectl rollout status deployment/graph-builder --namespace "$NAMESPACE" --timeout=300s
kubectl rollout status deployment/result-api --namespace "$NAMESPACE" --timeout=300s

# Open a local tunnel: localhost:18080 → result-api service port 80.
# The & runs it in the background; we record its PID to kill it on exit.
kubectl port-forward \
  --namespace "$NAMESPACE" \
  svc/result-api "$LOCAL_PORT":80 &>/dev/null &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT

# Give the tunnel 3 seconds to establish before hitting it.
sleep 3

BASE="http://localhost:$LOCAL_PORT"

# ── /health ───────────────────────────────────────────────────────────────────
echo "Checking /health..."
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE/health")
if [ "$HTTP_CODE" != "200" ]; then
  echo "FAIL: /health returned HTTP $HTTP_CODE"
  exit 1
fi
echo "PASS: /health returned 200"

# ── /analyze ──────────────────────────────────────────────────────────────────
# This call goes all the way through: result-api → analyzer → graph-builder →
# GitHub API (using the token from Secrets Manager). A failure here means
# either the upstream services are broken or the Secrets Manager secret for
# this environment is missing or wrong.
echo "Checking /analyze..."
RESPONSE=$(curl -sf -X POST "$BASE/analyze" \
  -H "Content-Type: application/json" \
  -d '{"repo_url":"https://github.com/panethjonathan8-ctrl/GitFlow"}')

STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))")
if [ "$STATUS" != "success" ]; then
  echo "FAIL: /analyze returned status='$STATUS'"
  echo "Full response: $RESPONSE"
  exit 1
fi
echo "PASS: /analyze returned status=success"

echo "=== Smoke test passed: $NAMESPACE ==="
