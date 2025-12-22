#!/usr/bin/env bash
set -euo pipefail

# Build and publish a single image if it does not already exist in GHCR.
# Inputs (env or args):
#   IMAGE_KEY (or first arg): key under .images in versions.json
#   OWNER (required): GitHub org/user
#   TOKEN (required): GitHub token with workflow/packages access
#   VERSIONS_PATH (optional): defaults to versions.json

IMAGE_KEY="${IMAGE_KEY:-${1:-}}"
OWNER="${OWNER:-}"
TOKEN="${TOKEN:-}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"

if [[ -z "${IMAGE_KEY}" ]]; then
  echo "IMAGE_KEY is required (image key in ${VERSIONS_PATH})" >&2
  exit 1
fi
if [[ -z "${OWNER}" ]]; then
  echo "OWNER is required" >&2
  exit 1
fi
if [[ -z "${TOKEN}" ]]; then
  echo "TOKEN is required" >&2
  exit 1
fi
if [[ ! -f "${VERSIONS_PATH}" ]]; then
  echo "versions file not found: ${VERSIONS_PATH}" >&2
  exit 1
fi

tmp_output=$(mktemp)
tmp_meta=$(mktemp)
cleanup() {
  rm -f "${tmp_output}" "${tmp_meta}"
}
trap cleanup EXIT

# Check existence
OWNER="${OWNER}" TOKEN="${TOKEN}" IMAGE_KEY="${IMAGE_KEY}" VERSIONS_PATH="${VERSIONS_PATH}" OUTPUT_PATH="${tmp_output}" scripts/check_image_exists.sh
image_exists=$(awk -F= '/image_exists/ {print $2}' "${tmp_output}" | tail -n1)

if [[ "${image_exists}" == "true" ]]; then
  echo "Image ${IMAGE_KEY} already exists; skipping build."
  exit 0
fi

# Get metadata
scripts/get_image_metadata.sh "${IMAGE_KEY}" "${tmp_meta}" "${VERSIONS_PATH}"
# shellcheck disable=SC1090
source "${tmp_meta}"

if [[ -z "${repo:-}" || -z "${ref:-}" ]]; then
  echo "Missing repo/ref for image ${IMAGE_KEY}" >&2
  exit 1
fi
if [[ -z "${revision_sha:-}" ]]; then
  echo "Missing revision_sha for image ${IMAGE_KEY}" >&2
  exit 1
fi

workflow_file="${PUBLISH_WORKFLOW_FILE:-.github/workflows/publish-image.yml}"
workflow_inputs=$(jq -nc --arg app "${IMAGE_KEY}" --arg rev "${revision_sha}" '{app_name:$app, revision:$rev}')

export GH_TOKEN="${TOKEN}"

if [[ "${SKIP_REMOTE:-}" == "true" || "${DRY_RUN:-}" == "true" ]]; then
  echo "SKIP_REMOTE/DRY_RUN set; would trigger ${repo}:${workflow_file} @ ${ref} for ${IMAGE_KEY} (revision ${revision_sha}); skipping dispatch."
  exit 0
fi

echo "Triggering workflow ${repo}:${workflow_file} @ ${ref} for image ${IMAGE_KEY} (revision ${revision_sha})"
scripts/run_workflow_with_wait.sh "${repo}" "${workflow_file}" "${ref}" "${workflow_inputs}"
