#!/usr/bin/env bash
set -euo pipefail

# Update websocket locals to point to the configured endpoint from versions.json; skips if green API is down.
# Runs only if: green_api_url exists in versions.json and the green API responds.
# Expects env:
#   ENV_NAME        - environment name (devnet/testnet/mainnet)
#   VERSIONS_PATH   - path to versions.json
#   TARGET_WS_KEY   - key under .environments[env] to read (default: green_websocket_server)
#   OWNER, TOKEN    - for v2_infra_apply.sh (passed through)
#   SERVICE_LIST    - services to include (passed through)
#   ACTION          - description (passed through)
#   JUST_TARGETS    - terraform targets (passed through)
#   GREEN_CHECK_TIMEOUT (optional, default: 10)

ENV_NAME="${ENV_NAME:?ENV_NAME required}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
TARGET_WS_KEY="${TARGET_WS_KEY:-green_websocket_server}"
GREEN_CHECK_TIMEOUT="${GREEN_CHECK_TIMEOUT:-10}"
SERVICE_LIST="${SERVICE_LIST:-kolme_green}"
ACTION="${ACTION:-reconfigure websocket endpoint}"
JUST_TARGETS="${JUST_TARGETS:-init plan apply}"
existing_extra_locals="${EXTRA_LOCALS:-}"

# Require green API to be reachable
green_api_url=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].green_api_url // empty' "${VERSIONS_PATH}")
if [[ -z "${green_api_url}" || "${green_api_url}" == "null" ]]; then
  echo "green_api_url missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi
if ! curl -fsSL --max-time "${GREEN_CHECK_TIMEOUT}" "${green_api_url}" >/dev/null 2>&1; then
  echo "Green API ${green_api_url} not reachable; skipping websocket reconfigure."
  exit 0
fi

# Fetch websocket value from versions.json
ws_value=$(jq -r --arg env "${ENV_NAME}" --arg key "${TARGET_WS_KEY}" '.environments[$env][$key] // empty' "${VERSIONS_PATH}")
if [[ -z "${ws_value}" || "${ws_value}" == "null" ]]; then
  echo "${TARGET_WS_KEY} missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

# Build EXTRA_LOCALS to set gossip_websockets_server
if [[ -n "${existing_extra_locals//[[:space:]]/}" ]]; then
  EXTRA_LOCALS="${existing_extra_locals}"$'\n'"gossip_websockets_server=${ws_value}"
else
  EXTRA_LOCALS="gossip_websockets_server=${ws_value}"
fi

export SERVICE_LIST ACTION JUST_TARGETS EXTRA_LOCALS ENV_NAME OWNER TOKEN VERSIONS_PATH
scripts/v2_infra_apply.sh
