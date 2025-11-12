#!/usr/bin/env bash
set -euo pipefail

FILE_PATH="${1:-versions.json}"
OWNER="${OWNER:?OWNER is required}"
TOKEN="${TOKEN:?TOKEN is required}"

resolved_any="false"

mapfile -t images < <(jq -r '.images | keys[]?' "${FILE_PATH}")

for image in "${images[@]}"; do
  repo=$(jq -r --arg img "$image" '.images[$img].repo' "${FILE_PATH}")
  ref=$(jq -r --arg img "$image" '.images[$img].ref' "${FILE_PATH}")

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
  image_tag="ghcr.io/${OWNER}/${image}:${resolved}"

  jq --arg img "${image}" --arg sha "${resolved}" --arg tag "${image_tag}" \
    '.images[$img].resolved_sha = $sha | .images[$img].resolved_image = $tag' \
    "${FILE_PATH}" > tmp && mv tmp "${FILE_PATH}"

  echo "Resolved ${image} (${ref}) -> ${resolved} (${image_tag})"
  resolved_any="true"
done

if [[ "${resolved_any}" != "true" ]]; then
  echo "No image refs required resolution."
fi
