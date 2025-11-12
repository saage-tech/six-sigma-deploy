#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:?environment required}"
SERVICE_NAME="${2:?service required}"
STAGES_JSON="${3:?stages json required}"

if [[ "${STAGES_JSON}" == "null" || -z "${STAGES_JSON}" ]]; then
  echo "No stages defined for ${SERVICE_NAME} in ${ENV_NAME}; skipping."
  exit 0
fi

echo "${STAGES_JSON}" | jq -r '.[]' | while read -r stage; do
  echo "::group::[${ENV_NAME}] ${SERVICE_NAME} stage: ${stage}"
  echo "Mocking execution of stage '${stage}' for ${SERVICE_NAME} on ${ENV_NAME}."
  echo "::endgroup::"
done
