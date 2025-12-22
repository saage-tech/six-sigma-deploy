#!/usr/bin/env bash
set -euo pipefail

# Update versions.json last_applied markers to the latest migration files
# for catalog-and-users-service and lsports-broker at the pinned revisions.
# Runs only if: ENV_NAME/OWNER/TOKEN provided and versions.json exists; reads migration files from GitHub.
#
# Env/args:
#   ENV_NAME (required or first arg)
#   OWNER (required) - GitHub org/user
#   TOKEN (required) - GitHub token with contents:read
#   VERSIONS_PATH (optional, default: versions.json)
#
# The script reads the migration files from GitHub (no local repo needed),
# picks the lexicographically latest filename for each service, and writes it
# to environments[env].migrations[...] .last_applied.

ENV_NAME="${ENV_NAME:-${1:-}}"
OWNER="${OWNER:-}"
TOKEN="${TOKEN:-}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"

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

get_sha_and_repo() {
  local image_key="$1"
  local sha repo override
  sha=$(jq -r --arg img "${image_key}" '.images[$img].revision_sha // empty' "${VERSIONS_PATH}")
  repo=$(jq -r --arg img "${image_key}" '.images[$img].repo // "six-sigma-kolme"' "${VERSIONS_PATH}")
  echo "${sha}:${repo}"
}

list_remote_migrations() {
  local repo="$1"
  local sha="$2"
  local dir="$3"
  local api_url="https://api.github.com/repos/${OWNER}/${repo}/git/trees/${sha}?recursive=1"
  curl -sSf \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${api_url}" \
  | jq -r --arg prefix "packages/${dir}/migrations/" '.tree[]?.path | select(startswith($prefix))' \
  | awk -F/ '{print $NF}' \
  | sort
}

services=("catalog-and-users-service:catalog" "lsports-broker:lsports-broker")
updates=()

for entry in "${services[@]}"; do
  svc="${entry%%:*}"
  image_key="${entry#*:}"
  sha_repo=$(get_sha_and_repo "${image_key}")
  sha="${sha_repo%%:*}"
  repo="${sha_repo#*:}"

  # Service-level installed_revision_sha override
  case "${svc}" in
    catalog-and-users-service)
      override=$(jq -r '.services["catalog_db_image"].installed_revision_sha // empty' "${VERSIONS_PATH}")
      ;;
    lsports-broker)
      override=$(jq -r '.services["broker_db_image"].installed_revision_sha // empty' "${VERSIONS_PATH}")
      ;;
    *)
      override=""
      ;;
  esac
  if [[ -n "${override}" && "${override}" != "null" ]]; then
    sha="${override}"
  fi

  if [[ -z "${sha}" || "${sha}" == "null" ]]; then
    echo "revision_sha missing for ${image_key}" >&2
    exit 1
  fi

  latest=""
  while IFS= read -r fname; do
    [[ -z "${fname}" ]] && continue
    latest="${fname}"
  done < <(list_remote_migrations "${repo}" "${sha}" "${svc}")

  if [[ -z "${latest}" ]]; then
    echo "No migrations found for ${svc} at ${sha}" >&2
    exit 1
  fi

  updates+=("${svc}:${latest}")
done

tmp=$(mktemp)
cp "${VERSIONS_PATH}" "${tmp}"

for entry in "${updates[@]}"; do
  svc="${entry%%:*}"
  fname="${entry#*:}"
  tmp2=$(mktemp)
  jq --arg env "${ENV_NAME}" --arg svc "${svc}" --arg fname "${fname}" \
    '.environments[$env].migrations[$svc].last_applied = $fname' \
    "${tmp}" > "${tmp2}"
  mv "${tmp2}" "${tmp}"
done

mv "${tmp}" "${VERSIONS_PATH}"
echo "Updated last_applied for ${ENV_NAME}: ${updates[*]}"
