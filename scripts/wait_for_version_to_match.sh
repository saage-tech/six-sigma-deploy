#!/usr/bin/env bash
set -euo pipefail

# Poll a chain API endpoint until code_version and chain_version both match
# the expected value, or fail after a timeout.
# Runs only if: TARGET_URL is reachable and exposes code_version/chain_version; fails on timeout/validation errors.
#
# Required:
#   TARGET_URL: chain/green API URL returning JSON with code_version and chain_version
#   TARGET_CODE_VERSION: expected version string
# Optional:
#   ENV_NAME / VERSIONS_PATH: if TARGET_URL is blank, derive from versions.json (.environments[env][API_URL_KEY])
#   API_URL_KEY: key under environments to read (default: chain_api_url)
#   TIMEOUT_SECONDS (default: 600)
#   SLEEP_SECONDS (default: 10)
#   MATCH_CHAIN_ONLY (default: false) - when true, succeed once chain_version matches target (ignores code_version)
#
# Exits 0 when both versions match; exits 1 on timeout or errors.

TARGET_URL="${TARGET_URL:-${1-}}"
TARGET_CODE_VERSION="${TARGET_CODE_VERSION:-${2-}}"
ENV_NAME="${ENV_NAME:-}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
API_URL_KEY="${API_URL_KEY:-chain_api_url}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"
SLEEP_SECONDS="${SLEEP_SECONDS:-10}"
MATCH_CHAIN_ONLY="${MATCH_CHAIN_ONLY:-false}"

if [[ -z "${TARGET_CODE_VERSION}" ]]; then
  echo "TARGET_CODE_VERSION (arg2) is required" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found on PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found on PATH" >&2
  exit 1
fi

# Derive TARGET_URL from versions.json if not provided
if [[ -z "${TARGET_URL}" ]]; then
  if [[ -z "${ENV_NAME}" ]]; then
    echo "TARGET_URL is required (set TARGET_URL or provide ENV_NAME with VERSIONS_PATH)" >&2
    exit 1
  fi
  if [[ ! -f "${VERSIONS_PATH}" ]]; then
    echo "VERSIONS_PATH '${VERSIONS_PATH}' not found" >&2
    exit 1
  fi
  TARGET_URL=$(jq -r --arg env "${ENV_NAME}" --arg key "${API_URL_KEY}" '.environments[$env][$key] // empty' "${VERSIONS_PATH}")
  if [[ -z "${TARGET_URL}" || "${TARGET_URL}" == "null" ]]; then
    echo "${API_URL_KEY} missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
    exit 1
  fi
fi

start_epoch=$(date +%s)
deadline=$((start_epoch + TIMEOUT_SECONDS))

while true; do
  now=$(date +%s)
  if (( now >= deadline )); then
    echo "Timed out waiting for code_version/chain_version to reach '${TARGET_CODE_VERSION}' (timeout ${TIMEOUT_SECONDS}s)" >&2
    exit 1
  fi

  body=$(curl -fsSL "${TARGET_URL}") || {
    echo "Request to ${TARGET_URL} failed; retrying..." >&2
    sleep "${SLEEP_SECONDS}"
    continue
  }

  code_version=$(jq -r '.code_version // empty' <<<"${body}")
  chain_version=$(jq -r '.chain_version // empty' <<<"${body}")

  if [[ -z "${code_version}" || -z "${chain_version}" ]]; then
    echo "Missing code_version or chain_version in response; retrying..." >&2
    sleep "${SLEEP_SECONDS}"
    continue
  fi

  echo "code_version=${code_version}, chain_version=${chain_version}, target=${TARGET_CODE_VERSION}"

  if [[ "${chain_version}" == "${TARGET_CODE_VERSION}" ]]; then
    if [[ "${MATCH_CHAIN_ONLY}" == "true" ]]; then
      echo "chain_version matches target '${TARGET_CODE_VERSION}' (code_version=${code_version}); accepting due to MATCH_CHAIN_ONLY=true."
      exit 0
    elif [[ "${code_version}" == "${TARGET_CODE_VERSION}" ]]; then
      echo "Versions match target '${TARGET_CODE_VERSION}'."
      exit 0
    fi
  fi

  sleep "${SLEEP_SECONDS}"
done
