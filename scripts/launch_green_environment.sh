#!/usr/bin/env bash
set -euo pipefail

# Launch green environment after verifying chain is stable and target CODE_VERSION differs.
# Runs only if: chain API reports code_version == chain_version (stable) AND target CODE_VERSION is different.
# Env vars:
#   ENV_NAME (required)
#   CODE_VERSION (required)
#   OWNER (required)
#   TOKEN (required) - GitHub token with contents:read for six-sigma-kolme
#   VERSIONS_PATH (optional, default: versions.json)
#   SKIP_REMOTE (optional) - passed through to v2_infra_apply.sh
#   GREEN_TIMEOUT_SECONDS (optional, default: 300 for post-launch wait)
#   GREEN_SLEEP_SECONDS (optional, default: 1 for post-launch wait)

ENV_NAME="${ENV_NAME:-}"
CODE_VERSION="${CODE_VERSION:-}"
OWNER="${OWNER:-}"
TOKEN="${TOKEN:-}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
CHAIN_API_KEY="chain_api_url"
GREEN_TIMEOUT_SECONDS="${GREEN_TIMEOUT_SECONDS:-300}"
GREEN_SLEEP_SECONDS="1"
launched=false

if [[ -z "${ENV_NAME}" ]]; then
  echo "ENV_NAME is required" >&2
  exit 1
fi
if [[ -z "${CODE_VERSION}" ]]; then
  if [[ -f "${VERSIONS_PATH}" ]]; then
    CODE_VERSION=$(jq -r '.images["kolme-app"].code_version // empty' "${VERSIONS_PATH}")
  fi
  if [[ -z "${CODE_VERSION}" || "${CODE_VERSION}" == "null" ]]; then
    echo "CODE_VERSION is required" >&2
    exit 1
  fi
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

# Verify current chain state (must be stable and different from target CODE_VERSION)
chain_api_url=$(jq -r --arg env "${ENV_NAME}" --arg key "${CHAIN_API_KEY}" '.environments[$env][$key] // empty' "${VERSIONS_PATH}")
if [[ -z "${chain_api_url}" || "${chain_api_url}" == "null" ]]; then
  echo "${CHAIN_API_KEY} missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

# Fetch green websocket endpoint for locals
green_ws=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].green_websocket_server // empty' "${VERSIONS_PATH}")
if [[ -z "${green_ws}" || "${green_ws}" == "null" ]]; then
  echo "green_websocket_server missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

chain_resp=$(curl -fsSL "${chain_api_url}") || {
  echo "Failed to query chain API at ${chain_api_url}" >&2
  exit 1
}
current_code_version=$(jq -r '.code_version // empty' <<<"${chain_resp}")
current_chain_version=$(jq -r '.chain_version // empty' <<<"${chain_resp}")

if [[ -z "${current_code_version}" || -z "${current_chain_version}" ]]; then
  echo "chain_api_url response missing code_version/chain_version; cannot validate stability" >&2
  exit 1
fi

if [[ "${current_code_version}" != "${current_chain_version}" ]]; then
  echo "Chain is not stable (code_version=${current_code_version}, chain_version=${current_chain_version}); cannot launch green." >&2
  exit 1
fi

if [[ "${current_chain_version}" == "${CODE_VERSION}" ]]; then
  echo "CODE_VERSION ${CODE_VERSION} already active on chain; skipping launch green."
  exit 0
fi

rev_sha=$(jq -r '.images["kolme-app"].revision_sha // empty' "${VERSIONS_PATH}")
if [[ -z "${rev_sha}" || "${rev_sha}" == "null" ]]; then
  echo "kolme-app.revision_sha missing in ${VERSIONS_PATH}" >&2
  exit 1
fi

api_url="https://api.github.com/repos/${OWNER}/six-sigma-kolme/contents/packages/kolme-app/src/app.rs?ref=${rev_sha}"
actual_cv=$(
  curl -sSf \
    -H "Accept: application/vnd.github.v3.raw" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${api_url}" \
  | sed -n -E 's/^.*CODE_VERSION.*"([^"]+)".*$/\1/p' \
  | head -n 1 || true)

if [[ -z "${actual_cv}" ]]; then
  echo "Unable to extract CODE_VERSION from ${api_url}" >&2
  exit 1
fi

if [[ "${actual_cv}" != "${CODE_VERSION}" ]]; then
  echo "CODE_VERSION mismatch: input '${CODE_VERSION}' vs app.rs '${actual_cv}' at ${rev_sha}" >&2
  exit 1
fi

SERVICE_LIST="kolme_green" \
ACTION="Launch green environment and upgrade chain to version ${CODE_VERSION}" \
JUST_TARGETS="init plan apply" \
EXTRA_LOCALS=$'new_chain_version='"${CODE_VERSION}"$'\ncreate_green_environment=true\ngossip_websockets_server='"${green_ws}" \
ENV_NAME="${ENV_NAME}" \
OWNER="${OWNER}" \
TOKEN="${TOKEN}" \
VERSIONS_PATH="${VERSIONS_PATH}" \
SKIP_REMOTE="${SKIP_REMOTE:-false}" \
bash scripts/v2_infra_apply.sh

if [[ "${SKIP_REMOTE:-false}" != "true" ]]; then
  launched=true
fi

if [[ "${launched}" == "true" ]]; then
  echo "Waiting for green API to report code_version/chain_version=${CODE_VERSION} (timeout ${GREEN_TIMEOUT_SECONDS}s)..."
  TARGET_CODE_VERSION="${CODE_VERSION}" \
  ENV_NAME="${ENV_NAME}" \
  VERSIONS_PATH="${VERSIONS_PATH}" \
  API_URL_KEY="green_api_url" \
  TIMEOUT_SECONDS="${GREEN_TIMEOUT_SECONDS}" \
  SLEEP_SECONDS="${GREEN_SLEEP_SECONDS}" \
  bash scripts/wait_for_version_to_match.sh
else
  echo "SKIP_REMOTE=true; not waiting for green readiness."
fi
