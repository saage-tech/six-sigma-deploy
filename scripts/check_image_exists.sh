#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${OUTPUT_PATH:-}"
REGISTRY="${REGISTRY:-}"
IMAGE_NAME="${IMAGE_NAME:-}"
REVISION_SHA="${REVISION_SHA:-}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
IMAGE_KEY="${IMAGE_KEY:-}"

# If IMAGE_KEY is provided, derive values from versions.json
if [[ -n "${IMAGE_KEY}" ]]; then
  if [[ ! -f "${VERSIONS_PATH}" ]]; then
    echo "versions file not found: ${VERSIONS_PATH}" >&2
    exit 1
  fi
  REGISTRY=$(jq -r '.registry // empty' "${VERSIONS_PATH}")
  IMAGE_NAME=$(jq -r --arg img "${IMAGE_KEY}" '.images[$img].image_name // $img // empty' "${VERSIONS_PATH}")
  REVISION_SHA=$(jq -r --arg img "${IMAGE_KEY}" '.images[$img].revision_sha // empty' "${VERSIONS_PATH}")
fi

if [[ -z "${IMAGE_NAME}" || "${IMAGE_NAME}" == "null" ]]; then
  echo "IMAGE_NAME is required" >&2
  exit 1
fi

if [[ -z "${REVISION_SHA}" || "${REVISION_SHA}" == "null" ]]; then
  echo "REVISION_SHA is required" >&2
  exit 1
fi

if [[ -z "${OUTPUT_PATH}" ]]; then
  echo "OUTPUT_PATH is required" >&2
  exit 1
fi

if [[ -z "${REGISTRY}" || "${REGISTRY}" == "null" ]]; then
  echo "REGISTRY is required" >&2
  exit 1
fi

package_name="${IMAGE_NAME}"
image_tag="${REVISION_SHA}"
image_ref="${REGISTRY%/}/${IMAGE_NAME}:${REVISION_SHA}"

write_result() {
  local exists_flag="$1"
  local msg="$2"
  echo "${msg}"
  echo "image_exists=${exists_flag}" >> "${OUTPUT_PATH}"
  exit 0
}

# Require Docker check only; assumes docker is already logged in.
if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI is required to check manifest existence" >&2
  exit 1
fi

inspect_output=$(docker manifest inspect "${image_ref}" 2>&1) && inspect_status=$? || inspect_status=$?

if [[ "${inspect_status}" -eq 0 ]]; then
  write_result "true" "Image tag ${image_tag} already exists at ${image_ref} (via docker manifest)"
fi

if echo "${inspect_output}" | grep -qiE 'denied|unauthorized|authentication required'; then
  echo "docker manifest inspect failed due to auth: ${inspect_output}" >&2
  exit 1
fi

write_result "false" "Image tag ${image_tag} not found at ${image_ref} (via docker manifest)"
