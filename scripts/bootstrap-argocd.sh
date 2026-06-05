#!/bin/bash
# Registers the gitflow-analyzer Application with ArgoCD.
# Safe to run on every deploy — kubectl apply is idempotent.
# If ArgoCD is not yet ready (e.g. cluster just created), the script exits
# cleanly so the rest of the pipeline is not blocked.
set -e

echo "Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server \
  --namespace argocd \
  --timeout=120s || {
  echo "ArgoCD not ready — skipping application bootstrap"
  exit 0
}

echo "Applying ArgoCD Application manifest..."
kubectl apply -f k8s/argocd/application.yaml
echo "ArgoCD Application registered — sync will begin within ~3 minutes"
