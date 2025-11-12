#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:?image name required}"
IMAGE_TAG="${2:-}"
OUTPUT_PATH="${3:?output path required}"
OWNER="${OWNER:-}"
TOKEN="${TOKEN:-}"

if [[ -z "${IMAGE_TAG}" || "${IMAGE_TAG}" == "null" ]]; then
  echo "image_exists=false" >> "${OUTPUT_PATH}"
  exit 0
fi

tmp=$(mktemp)
org_url="https://api.github.com/orgs/${OWNER}/packages/container/${IMAGE_NAME}/versions?per_page=100"
user_url="https://api.github.com/users/${OWNER}/packages/container/${IMAGE_NAME}/versions?per_page=100"

status=$(curl -s -o "${tmp}" -w "%{http_code}" \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  "${org_url}")

if [[ "${status}" -eq 404 ]]; then
  status=$(curl -s -o "${tmp}" -w "%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${user_url}")
fi

if [[ "${status}" -lt 400 ]] && jq -e --arg tag "${IMAGE_TAG}" '.[] | select(.metadata.container.tags[]? == $tag)' "${tmp}" >/dev/null; then
  echo "Image tag ${IMAGE_TAG} already exists in ghcr.io/${OWNER}/${IMAGE_NAME}"
  echo "image_exists=true" >> "${OUTPUT_PATH}"
else
  echo "Image tag ${IMAGE_TAG} not found in ghcr.io/${OWNER}/${IMAGE_NAME}"
  echo "image_exists=false" >> "${OUTPUT_PATH}"
fi

rm -f "${tmp}"
