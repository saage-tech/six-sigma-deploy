#!/usr/bin/env bash
set -euo pipefail

FILE_PATH="${1:-versions.json}"
RELEASE_TYPE_INPUT="${RELEASE_TYPE_INPUT:-}"
INPUTS_JSON="${INPUTS_JSON:-}"

updated="false"

if [[ -n "${RELEASE_TYPE_INPUT}" ]]; then
  jq --arg rt "${RELEASE_TYPE_INPUT}" '.release_type = $rt' "${FILE_PATH}" > tmp && mv tmp "${FILE_PATH}"
  updated="true"
fi

if [[ -n "${INPUTS_JSON}" && "${INPUTS_JSON}" != "null" ]]; then
  for input in $(echo "${INPUTS_JSON}" | jq -r 'keys[] | select(startswith("image_"))'); do
    value=$(echo "${INPUTS_JSON}" | jq -r --arg i "$input" '.[$i]')
    if [[ -z "${value}" || "${value}" == "null" ]]; then
      echo "Skipping ${input} (blank)"
      continue
    fi

    image="${input#image_}"
    image="${image%_ref}"
    image="${image//_/-}"

    echo "Updating image '${image}' to ref '${value}'"
    jq --arg img "${image}" --arg ref "${value}" '.images[$img].ref = $ref' "${FILE_PATH}" > tmp && mv tmp "${FILE_PATH}"
    updated="true"
  done
fi

if [[ "${updated}" == "true" ]]; then
  echo "versions.json updated from manual inputs."
else
  echo "No manual overrides supplied."
fi
