#!/usr/bin/env bash
set -euo pipefail

# Update blue environment when chain_version == green code_version and chain_version != chain code_version.
# Runs only if: green_api_url and chain_api_url exist; green API reachable; above version conditions hold.
# Skips if green API is unreachable. Errors if required URLs are missing from versions.json.
# After dispatch (and when not SKIP_REMOTE), waits for chain to converge to the target version.
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
BLUE_WAIT_TIMEOUT="${BLUE_WAIT_TIMEOUT:-600}"
BLUE_WAIT_SLEEP="${BLUE_WAIT_SLEEP:-10}"
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
chain_api_url=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].chain_api_url // empty' "${VERSIONS_PATH}")

if [[ -z "${green_api_url}" || "${green_api_url}" == "null" ]]; then
  echo "green_api_url missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi
if [[ -z "${chain_api_url}" || "${chain_api_url}" == "null" ]]; then
  echo "chain_api_url missing for env '${ENV_NAME}' in ${VERSIONS_PATH}" >&2
  exit 1
fi

if ! green_resp=$(curl -fsSL --max-time 10 "${green_api_url}" 2>/dev/null); then
  echo "Green API ${green_api_url} not reachable; skipping blue update."
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
chain_code_version=$(jq -r '.code_version // empty' <<<"${chain_resp}")
chain_chain_version=$(jq -r '.chain_version // empty' <<<"${chain_resp}")
if [[ -z "${chain_code_version}" || -z "${chain_chain_version}" || "${chain_code_version}" == "null" || "${chain_chain_version}" == "null" ]]; then
  echo "code_version/chain_version missing from chain API response at ${chain_api_url}" >&2
  exit 1
fi

if [[ "${chain_chain_version}" != "${green_code_version}" ]]; then
  echo "Chain chain_version (${chain_chain_version}) does not match green code_version (${green_code_version}); skipping blue update."
  exit 0
fi

if [[ "${chain_code_version}" == "${chain_chain_version}" ]]; then
  echo "Chain code_version (${chain_code_version}) already equals chain_version (${chain_chain_version}); skipping blue update."
  exit 0
fi

echo "Updating blue environment: chain_version=${chain_chain_version}, chain code_version=${chain_code_version}, green code_version=${green_code_version}"

SERVICE_LIST="kolme_processor,kolme_listener,kolme_approver,kolme_api_server,kolme_submitter,kolme_archiver" \
ACTION="update blue environment" \
JUST_TARGETS="init plan apply" \
EXTRA_LOCALS=$'new_chain_version=null' \
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
  echo "Waiting for chain to converge to code_version=${green_code_version} (timeout ${BLUE_WAIT_TIMEOUT}s)..."
  TARGET_CODE_VERSION="${green_code_version}" \
  ENV_NAME="${ENV_NAME}" \
  VERSIONS_PATH="${VERSIONS_PATH}" \
  API_URL_KEY="chain_api_url" \
  TIMEOUT_SECONDS="${BLUE_WAIT_TIMEOUT}" \
  SLEEP_SECONDS="${BLUE_WAIT_SLEEP}" \
  bash scripts/wait_for_version_to_match.sh
else
  echo "SKIP_REMOTE=true; not waiting for blue convergence."
fi
