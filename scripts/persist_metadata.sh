#!/usr/bin/env bash
set -euo pipefail

FILE_PATH="${1:-versions.json}"

if git diff --quiet --exit-code "${FILE_PATH}"; then
  echo "No metadata changes to commit."
  exit 0
fi

git config user.name "github-actions"
git config user.email "github-actions@users.noreply.github.com"
git add "${FILE_PATH}"
git commit -m "chore: update version metadata"
git push
