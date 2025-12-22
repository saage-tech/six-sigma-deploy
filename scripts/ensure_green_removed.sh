#!/usr/bin/env bash
set -euo pipefail

# Wait until the green endpoint is no longer reachable (HTTP failure), or timeout.
# Runs only if: the target URL key exists in versions.json; fails on timeout if still reachable.
# Env:
#   ENV_NAME         - environment name
#   VERSIONS_PATH    - path to versions.json (default: versions.json)
#   API_URL_KEY      - key under environments[env] to read (default: green_api_url)
#   TIMEOUT_SECONDS  - optional, default 300
#   SLEEP_SECONDS    - optional, default 10

ENV_NAME="${ENV_NAME:?ENV_NAME required}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
API_URL_KEY="${API_URL_KEY:-green_api_url}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
SLEEP_SECONDS="${SLEEP_SECONDS:-10}"

if [[ ! -f "${VERSIONS_PATH}" ]]; then
  echo "versions file not found: ${VERSIONS_PATH}" >&2
  exit 1
fi

TARGET_URL=$(jq -r --arg env "${ENV_NAME}" --arg key "${API_URL_KEY}" '.environments[$env][$key] // empty' "${VERSIONS_PATH}")
if [[ -z "${TARGET_URL}" || "${TARGET_URL}" == "null" ]]; then
  echo "${API_URL_KEY} missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

start=$(date +%s)
deadline=$((start + TIMEOUT_SECONDS))

while true; do
  now=$(date +%s)
  if (( now >= deadline )); then
    echo "Timed out waiting for green endpoint to be unreachable (${TARGET_URL})" >&2
    exit 1
  fi

  if ! curl -fsS "${TARGET_URL}" >/dev/null 2>&1; then
    echo "Green endpoint no longer reachable at ${TARGET_URL}"
    exit 0
  fi

  echo "Green endpoint still reachable; retrying..."
  sleep "${SLEEP_SECONDS}"
done
