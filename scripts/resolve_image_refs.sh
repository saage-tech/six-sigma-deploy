#!/usr/bin/env bash
set -euo pipefail

VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
OWNER="${OWNER:?OWNER is required}"
TOKEN="${TOKEN:?TOKEN is required}"

resolved_any="false"
registry=$(jq -r '.registry // empty' "${VERSIONS_PATH}")

if [[ -z "${registry}" || "${registry}" == "null" ]]; then
  echo "registry is required in ${VERSIONS_PATH}" >&2
  exit 1
fi

images=()
while IFS= read -r img; do
  images+=("$img")
done < <(jq -r '.images | keys[]?' "${VERSIONS_PATH}")

for image in "${images[@]}"; do
  repo=$(jq -r --arg img "$image" '.images[$img].repo' "${VERSIONS_PATH}")
  image_name=$(jq -r --arg img "$image" '.images[$img].image_name // empty' "${VERSIONS_PATH}")
  ref=$(jq -r --arg img "$image" '.images[$img].ref' "${VERSIONS_PATH}")

  if [[ -z "${ref}" || "${ref}" == "null" ]]; then
    echo "Skipping ${image} (no ref defined)"
    continue
  fi

  if [[ "${ref}" == refs/* ]]; then
    ref_path="${ref#refs/}"
  else
    ref_path="heads/${ref}"
  fi

  encoded_ref=$(jq -rn --arg r "${ref_path}" '$r|@uri')
  api_url="https://api.github.com/repos/${OWNER}/${repo}/git/ref/${encoded_ref}"

  response=$(curl -sSf \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${api_url}") || {
      echo "Unable to resolve ${image} ref '${ref}' via ${api_url}"
      exit 1
    }

  resolved=$(echo "${response}" | jq -r '.object.sha')
  package_name="${image_name:-$image}"

  jq --arg img "${image}" --arg sha "${resolved}" --arg pkg "${package_name}" \
    '.images[$img].revision_sha = $sha | .images[$img].image_name = (.images[$img].image_name // $pkg)' \
    "${VERSIONS_PATH}" > tmp && mv tmp "${VERSIONS_PATH}"

  echo "Resolved ${image} (${ref}) -> ${resolved} (${registry}/${package_name}:${resolved})"
  resolved_any="true"
done

if [[ "${resolved_any}" != "true" ]]; then
  echo "No image refs required resolution."
fi
