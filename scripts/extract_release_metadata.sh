#!/usr/bin/env bash
set -euo pipefail

FILE_PATH="${1:-versions.json}"
OUTPUT_PATH="${2:?output path required}"

release_type=$(jq -r '.release_type // "release"' "${FILE_PATH}")
images=$(jq -c '.images | to_entries | map({image: .key} + .value) // []' "${FILE_PATH}")

{
  echo "release_type=${release_type}"
  echo "images=${images}"
} >> "${OUTPUT_PATH}"

echo "Release type detected: ${release_type}"
