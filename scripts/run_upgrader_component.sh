#!/usr/bin/env bash
set -euo pipefail

# Run upgrader component if chain chain_version differs from green code_version.
# Runs only if: green_api_url exists and is reachable; chain_api_url exists; chain_chain_version != green code_version.
# Skips if green API is unreachable. Errors if required URLs are missing.
# After dispatch (and when not SKIP_REMOTE), waits for chain_version to reach green code_version.
#
# Env/args:
#   ENV_NAME (required or first arg)
#   OWNER (required)
#   TOKEN (required)
#   VERSIONS_PATH (optional, default: versions.json)
#   SKIP_REMOTE (optional, default: false)

ENV_NAME="${ENV_NAME:-${1:-}}"
OWNER="${OWNER:-}"
TOKEN="${TOKEN:-}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
SKIP_REMOTE="${SKIP_REMOTE:-false}"
UPGRADER_WAIT_TIMEOUT="${UPGRADER_WAIT_TIMEOUT:-600}"
UPGRADER_WAIT_SLEEP="${UPGRADER_WAIT_SLEEP:-10}"
dispatched=false
shift || true

if [[ -z "${ENV_NAME}" ]]; then
  echo "ENV_NAME is required" >&2
  exit 1
fi
if [[ -z "${OWNER}" ]]; then
  echo "OWNER is required" >&2
  exit 1
fi
if [[ -z "${TOKEN}" ]]; then
  echo "TOKEN is required" >&2
  exit 1
fi
if [[ ! -f "${VERSIONS_PATH}" ]]; then
  echo "versions file not found: ${VERSIONS_PATH}" >&2
  exit 1
fi

green_api_url=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].green_api_url // empty' "${VERSIONS_PATH}")
if [[ -z "${green_api_url}" || "${green_api_url}" == "null" ]]; then
  echo "green_api_url missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

chain_api_url=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].chain_api_url // empty' "${VERSIONS_PATH}")
if [[ -z "${chain_api_url}" || "${chain_api_url}" == "null" ]]; then
  echo "chain_api_url missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

if ! green_resp=$(curl -fsSL --max-time 10 "${green_api_url}" 2>/dev/null); then
  echo "Green API ${green_api_url} not reachable; skipping upgrader component."
  exit 0
fi

green_code_version=$(jq -r '.code_version // empty' <<<"${green_resp}")
if [[ -z "${green_code_version}" || "${green_code_version}" == "null" ]]; then
  echo "code_version missing from green API response at ${green_api_url}" >&2
  exit 1
fi

chain_resp=$(curl -fsSL --max-time 10 "${chain_api_url}" 2>/dev/null) || {
  echo "Chain API ${chain_api_url} not reachable; cannot compare versions." >&2
  exit 1
}
chain_chain_version=$(jq -r '.chain_version // empty' <<<"${chain_resp}")
if [[ -z "${chain_chain_version}" || "${chain_chain_version}" == "null" ]]; then
  echo "chain_version missing from chain API response at ${chain_api_url}" >&2
  exit 1
fi

if [[ "${chain_chain_version}" == "${green_code_version}" ]]; then
  echo "Chain chain_version (${chain_chain_version}) already matches target (${green_code_version}); skipping upgrader component."
  exit 0
fi

echo "Chain chain_version (${chain_chain_version}) differs from target (${green_code_version}); running upgrader component."

SERVICE_LIST="kolme_green" \
ACTION="execute upgrader component" \
JUST_TARGETS="init plan apply" \
EXTRA_LOCALS=$'new_chain_version='"${green_code_version}" \
ENV_NAME="${ENV_NAME}" \
OWNER="${OWNER}" \
TOKEN="${TOKEN}" \
VERSIONS_PATH="${VERSIONS_PATH}" \
SKIP_REMOTE="${SKIP_REMOTE}" \
bash scripts/v2_infra_apply.sh

if [[ "${SKIP_REMOTE}" != "true" ]]; then
  dispatched=true
fi

if [[ "${dispatched}" == "true" ]]; then
  echo "Waiting for chain_version to reach ${green_code_version} (timeout ${UPGRADER_WAIT_TIMEOUT}s; MATCH_CHAIN_ONLY=true)..."
  TARGET_CODE_VERSION="${green_code_version}" \
  ENV_NAME="${ENV_NAME}" \
  VERSIONS_PATH="${VERSIONS_PATH}" \
  API_URL_KEY="chain_api_url" \
  TIMEOUT_SECONDS="${UPGRADER_WAIT_TIMEOUT}" \
  SLEEP_SECONDS="${UPGRADER_WAIT_SLEEP}" \
  MATCH_CHAIN_ONLY="true" \
  bash scripts/wait_for_version_to_match.sh
else
  echo "SKIP_REMOTE=true; not waiting for upgrader convergence."
fi
