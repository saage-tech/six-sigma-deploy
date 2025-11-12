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

export GH_TOKEN="${TOKEN}"

exists_id=$(
  gh api "/orgs/${OWNER}/packages/container/${IMAGE_NAME}/versions" \
    --paginate \
    --jq ".[] | select(.metadata.container.tags[]? == \"${IMAGE_TAG}\") | .id" 2>/dev/null | head -n 1
) || true

if [[ -z "${exists_id}" ]]; then
  exists_id=$(
    gh api "/users/${OWNER}/packages/container/${IMAGE_NAME}/versions" \
      --paginate \
      --jq ".[] | select(.metadata.container.tags[]? == \"${IMAGE_TAG}\") | .id" 2>/dev/null | head -n 1
  ) || true
fi

if [[ -n "${exists_id}" ]]; then
  echo "Image tag ${IMAGE_TAG} already exists in ghcr.io/${OWNER}/${IMAGE_NAME}"
  echo "image_exists=true" >> "${OUTPUT_PATH}"
else
  echo "Image tag ${IMAGE_TAG} not found in ghcr.io/${OWNER}/${IMAGE_NAME}"
  echo "image_exists=false" >> "${OUTPUT_PATH}"
fi
