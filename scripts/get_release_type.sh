#!/usr/bin/env bash
set -euo pipefail

VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"

release_type=$(jq -r '.release_type // "pre-release"' "${VERSIONS_PATH}")

echo "${release_type}"
