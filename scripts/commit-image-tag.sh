#!/bin/bash
# Commits the updated image tag in values-dev.yaml back to main.
# Called by the deploy-eks CI job after update-image-tag.py runs.
# Pushes made with GITHUB_TOKEN do not re-trigger GitHub Actions workflows,
# so there is no risk of an infinite deploy loop.
set -e

TAG="$1"

if [ -z "$TAG" ]; then
  echo "Usage: $0 <image-tag>"
  exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Stage the file BEFORE pulling — git pull --rebase fails if there are unstaged changes
git add k8s/helm/gitflow-analyzer/values-dev.yaml
git pull --rebase origin main
git commit -m "chore: deploy image tag ${TAG} to EKS"
git push origin main
