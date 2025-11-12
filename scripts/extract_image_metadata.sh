#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:?image name required}"
OUTPUT_PATH="${2:?output path required}"
IMAGES_JSON="${IMAGES_JSON:-}"

if [[ -z "${IMAGES_JSON}" || "${IMAGES_JSON}" == "null" ]]; then
  echo "No images metadata available for ${IMAGE_NAME}" >&2
  exit 1
fi

record=$(echo "${IMAGES_JSON}" | jq -c --arg name "${IMAGE_NAME}" '.[] | select(.image == $name)')

if [[ -z "${record}" ]]; then
  echo "Image ${IMAGE_NAME} not found in metadata" >&2
  exit 1
fi

repo=$(echo "${record}" | jq -r '.repo')
workflow=$(echo "${record}" | jq -r '.workflow')
ref=$(echo "${record}" | jq -r '.ref')
resolved_sha=$(echo "${record}" | jq -r '.resolved_sha')

{
  echo "repo=${repo}"
  echo "workflow=${workflow}"
  echo "ref=${ref}"
  echo "resolved_sha=${resolved_sha}"
} >> "${OUTPUT_PATH}"
