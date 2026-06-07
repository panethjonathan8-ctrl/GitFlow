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

# Commit first, then rebase onto main.
# git pull --rebase refuses to run if the index has staged changes, so we
# commit before pulling. The rebase then replays our commit on top of any
# new commits that landed on main while the build was running.
git add k8s/helm/gitflow-analyzer/values-dev.yaml
git commit -m "chore: deploy image tag ${TAG} to EKS"
git pull --rebase origin main
git push origin main
