#!/usr/bin/env bash

set -euo pipefail

./tools/generate_sdk_versions.py
./tools/generate_ndk_versions.py

if git diff --quiet; then
  echo "No version updates found."
  exit 0
fi

timestamp="$(date -u +%Y%m%d%H%M%S)"
branch="automation/update-versions-${timestamp}"
base_branch="${GITHUB_REF_NAME:-$(git branch --show-current)}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git checkout -b "$branch"
git add -A
git commit -m "Update versions"
git push origin "$branch"

gh pr create \
  --repo "$GITHUB_REPOSITORY" \
  --base "$base_branch" \
  --head "$branch" \
  --title "Update versions"
