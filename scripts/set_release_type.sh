#!/usr/bin/env bash
set -euo pipefail

VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
INPUT="${1:-${RELEASE_TYPE_INPUT:-}}"

if [[ -z "${INPUT}" || "${INPUT}" == "null" ]]; then
  echo "No release_type override provided; keeping existing value from ${VERSIONS_PATH}"
  exit 0
fi

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

jq --arg rt "${INPUT}" '.release_type = $rt' "${VERSIONS_PATH}" > "${tmp_file}"
mv "${tmp_file}" "${VERSIONS_PATH}"

echo "release_type set to '${INPUT}' in ${VERSIONS_PATH}"
