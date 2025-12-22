#!/usr/bin/env bash
set -euo pipefail

# Remove green environment when chain is in sync and green is reachable.
# Runs only if: chain_api_url and green_api_url exist; chain code_version == chain_version; green API reachable.
# Also resets websocket_server to the primary value from versions.json during removal.
# Errors if chain/green URLs are missing from versions.json.
# After dispatch (and when not SKIP_REMOTE), waits for green endpoint to disappear.
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
GREEN_REMOVE_TIMEOUT="${GREEN_REMOVE_TIMEOUT:-600}"
GREEN_REMOVE_SLEEP="${GREEN_REMOVE_SLEEP:-10}"
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

chain_api_url=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].chain_api_url // empty' "${VERSIONS_PATH}")
green_api_url=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].green_api_url // empty' "${VERSIONS_PATH}")
websocket_server=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].websocket_server // empty' "${VERSIONS_PATH}")

if [[ -z "${chain_api_url}" || "${chain_api_url}" == "null" ]]; then
  echo "chain_api_url missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi
if [[ -z "${green_api_url}" || "${green_api_url}" == "null" ]]; then
  echo "green_api_url missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi
if [[ -z "${websocket_server}" || "${websocket_server}" == "null" ]]; then
  echo "websocket_server missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

chain_resp=$(curl -fsSL --max-time 10 "${chain_api_url}" 2>/dev/null) || {
  echo "Chain API ${chain_api_url} not reachable; cannot remove green." >&2
  exit 1
}
chain_code_version=$(jq -r '.code_version // empty' <<<"${chain_resp}")
chain_chain_version=$(jq -r '.chain_version // empty' <<<"${chain_resp}")
if [[ -z "${chain_code_version}" || -z "${chain_chain_version}" || "${chain_code_version}" == "null" || "${chain_chain_version}" == "null" ]]; then
  echo "code_version/chain_version missing from chain API response at ${chain_api_url}" >&2
  exit 1
fi

if [[ "${chain_code_version}" != "${chain_chain_version}" ]]; then
  echo "Chain not in sync (code_version=${chain_code_version}, chain_version=${chain_chain_version}); skipping green removal."
  exit 0
fi

if ! curl -fsSL --max-time 10 "${green_api_url}" >/dev/null 2>&1; then
  echo "Green API ${green_api_url} not reachable; skipping green removal."
  exit 0
fi

echo "Removing green environment for ${ENV_NAME} (chain_version=${chain_chain_version})."

SERVICE_LIST="kolme_green" \
ACTION="remove green environment" \
JUST_TARGETS="init plan apply" \
EXTRA_LOCALS=$'create_green_environment=false\nwebsocket_server='"${websocket_server}" \
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
  echo "Waiting for green endpoint to be removed (timeout ${GREEN_REMOVE_TIMEOUT}s)..."
  ENV_NAME="${ENV_NAME}" \
  VERSIONS_PATH="${VERSIONS_PATH}" \
  API_URL_KEY="green_api_url" \
  TIMEOUT_SECONDS="${GREEN_REMOVE_TIMEOUT}" \
  SLEEP_SECONDS="${GREEN_REMOVE_SLEEP}" \
  bash scripts/ensure_green_removed.sh
else
  echo "SKIP_REMOTE=true; not waiting for green removal."
fi
