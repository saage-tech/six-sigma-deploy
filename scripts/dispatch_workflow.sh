#!/usr/bin/env bash
set -euo pipefail

OWNER="${OWNER:?OWNER required}"
REPO="${1:?repo required}"
WORKFLOW_PATH="${2:?workflow path required}"
REF="${3:?ref required}"
TOKEN="${TOKEN:?TOKEN required}"

workflow_file=$(basename "${WORKFLOW_PATH}")
dispatch_url="https://api.github.com/repos/${OWNER}/${REPO}/actions/workflows/${workflow_file}/dispatches"

echo "Dispatching ${OWNER}/${REPO}@${REF} workflow ${workflow_file}"

curl -sSf -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${dispatch_url}" \
  -d "$(jq -n --arg ref "${REF}" '{ref: $ref}')"
