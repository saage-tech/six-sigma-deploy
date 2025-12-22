#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:?image name required}"
OUTPUT_PATH="${2:?output path required}"
VERSIONS_PATH="${3:-versions.json}"
SERVICE_NAME="${SERVICE_NAME:-}"

if ! jq -e --arg img "${IMAGE_NAME}" '.images[$img]' "${VERSIONS_PATH}" >/dev/null; then
  echo "Image '${IMAGE_NAME}' not found in ${VERSIONS_PATH}" >&2
  exit 1
fi

fields=(
  repo
  workflow
  ref
  image
  image_name
  revision_sha
  registry
)

# If a service-specific override is present, prefer it for revision_sha (installed_revision_sha)
if [[ -n "${SERVICE_NAME}" ]]; then
  service_rev=$(jq -r --arg svc "${SERVICE_NAME}" '.services[$svc].installed_revision_sha // empty' "${VERSIONS_PATH}")
  if [[ -n "${service_rev}" && "${service_rev}" != "null" ]]; then
    echo "revision_sha=${service_rev}" >> "${OUTPUT_PATH}"
  fi
fi

for field in "${fields[@]}"; do
  value=$(jq -r --arg img "${IMAGE_NAME}" --arg field "${field}" '
    if $field == "registry" then (.images[$img][$field] // .registry // empty)
    elif $field == "image_name" then (.images[$img][$field] // $img)
    else (.images[$img][$field] // empty)
    end
  ' "${VERSIONS_PATH}")
  if [[ -n "${value}" ]]; then
    echo "${field}=${value}" >> "${OUTPUT_PATH}"
  fi
done

# Compute resolved_image for convenience if components are present
registry=$(jq -r '.registry // empty' "${VERSIONS_PATH}")
image_registry=$(jq -r --arg img "${IMAGE_NAME}" '.images[$img].registry // empty' "${VERSIONS_PATH}")
registry="${image_registry:-${registry}}"
image_name_val=$(jq -r --arg img "${IMAGE_NAME}" '.images[$img].image_name // $img' "${VERSIONS_PATH}")
revision_val=$(jq -r --arg img "${IMAGE_NAME}" '.images[$img].revision_sha // empty' "${VERSIONS_PATH}")
if [[ -n "${registry}" && "${registry}" != "null" && -n "${revision_val}" && "${revision_val}" != "null" ]]; then
  echo "resolved_image=${registry}/${image_name_val}:${revision_val}" >> "${OUTPUT_PATH}"
fi
