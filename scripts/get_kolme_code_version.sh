#!/usr/bin/env bash
set -euo pipefail

# Derive CODE_VERSION from the Kolme source at the revision specified in versions.json
# by fetching app.rs from GitHub (no local repo required).
# Env:
#   VERSIONS_PATH (default: versions.json)
#   OWNER (required)
#   TOKEN (required) GitHub token with contents:read
#   GITHUB_OUTPUT (optional) to emit code_version

VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
OWNER="${OWNER:?OWNER is required}"
TOKEN="${TOKEN:?TOKEN is required}"

if [[ ! -f "${VERSIONS_PATH}" ]]; then
  echo "versions file not found: ${VERSIONS_PATH}" >&2
  exit 1
fi

repo="six-sigma-kolme"
revision_sha=$(jq -r '.images["kolme-app"].revision_sha // empty' "${VERSIONS_PATH}")

if [[ -z "${revision_sha}" || "${revision_sha}" == "null" ]]; then
  echo "kolme-app.revision_sha missing in ${VERSIONS_PATH}" >&2
  exit 1
fi

api_url="https://api.github.com/repos/${OWNER}/${repo}/contents/packages/kolme-app/src/app.rs?ref=${revision_sha}"

code_version=$(
  curl -sSf \
    -H "Accept: application/vnd.github.v3.raw" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${api_url}" \
  | sed -n -E 's/^.*CODE_VERSION.*"([^"]+)".*$/\1/p' \
  | head -n 1 || true)

if [[ -z "${code_version}" ]]; then
  echo "Unable to extract CODE_VERSION from ${api_url}" >&2
  exit 1
fi

# Persist into versions.json (for the kolme-app image)
jq --arg cv "${code_version}" '.images["kolme-app"].code_version = $cv' "${VERSIONS_PATH}" > tmp && mv tmp "${VERSIONS_PATH}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "code_version=${code_version}" >> "${GITHUB_OUTPUT}"
else
  echo "${code_version}"
fi
