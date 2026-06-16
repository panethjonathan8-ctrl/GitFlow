#!/bin/bash
# Registers the three gitflow-analyzer ArgoCD Applications (dev/staging/production).
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

echo "Applying ArgoCD Application manifests..."
kubectl apply -f k8s/argocd/application-dev.yaml
kubectl apply -f k8s/argocd/application-staging.yaml
kubectl apply -f k8s/argocd/application-production.yaml

# Remove the old single-namespace Application if it still exists from before
# the multi-env migration. The finalizer deletes all resources it managed
# in the gitflow-analyzer namespace as part of the deletion.
if kubectl get application gitflow-analyzer -n argocd &>/dev/null; then
  echo "Removing legacy Application gitflow-analyzer (replaced by gitflow-analyzer-dev)..."
  kubectl delete application gitflow-analyzer -n argocd
fi

echo "ArgoCD Applications registered — syncs will begin within ~3 minutes"
