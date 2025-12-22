#!/usr/bin/env bash
set -euo pipefail

# Determine if catalog/lsports migrations have pending files beyond the last_applied
# recorded in versions.json for a given environment.
#
# Usage: check_pending_migrations.sh <env> [versions_path]
# Outputs: "migrations_needed=true|false" and exits 0 if pending, 1 otherwise.
#
# Logic: lists migration files at the resolved image shas for catalog-service and
# lsports-broker via the GitHub tree API (no local repo required). If any migration
# filename is lexicographically greater than the recorded last_applied (or
# last_applied is null/empty), migrations are needed.

ENV_NAME="${ENV_NAME:-${1:-}}"
VERSIONS_PATH="${VERSIONS_PATH:-${2:-versions.json}}"
OWNER="${OWNER:-}"
TOKEN="${TOKEN:-}"

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

catalog_sha=$(jq -r '.images["catalog-service"].revision_sha // empty' "${VERSIONS_PATH}")
broker_sha=$(jq -r '.images["lsports-broker"].revision_sha // empty' "${VERSIONS_PATH}")
catalog_repo=$(jq -r '.images["catalog-service"].repo // "six-sigma-kolme"' "${VERSIONS_PATH}")
broker_repo=$(jq -r '.images["lsports-broker"].repo // "six-sigma-kolme"' "${VERSIONS_PATH}")
catalog_last=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].migrations["catalog-and-users-service"].last_applied // empty' "${VERSIONS_PATH}")
broker_last=$(jq -r --arg env "${ENV_NAME}" '.environments[$env].migrations["lsports-broker"].last_applied // empty' "${VERSIONS_PATH}")

# Service-level overrides
catalog_override=$(jq -r --arg env "${ENV_NAME}" '.services["catalog_db_image"].installed_revision_sha // empty' "${VERSIONS_PATH}")
broker_override=$(jq -r --arg env "${ENV_NAME}" '.services["broker_db_image"].installed_revision_sha // empty' "${VERSIONS_PATH}")

if [[ -n "${catalog_override}" && "${catalog_override}" != "null" ]]; then
  catalog_sha="${catalog_override}"
fi
if [[ -n "${broker_override}" && "${broker_override}" != "null" ]]; then
  broker_sha="${broker_override}"
fi

if [[ -z "${catalog_sha}" || -z "${broker_sha}" ]]; then
  echo "missing revision_sha for catalog-service or lsports-broker in ${VERSIONS_PATH}" >&2
  exit 1
fi

has_pending=false

list_remote_migrations() {
  local repo="$1"
  local sha="$2"
  local dir="$3"

  api_url="https://api.github.com/repos/${OWNER}/${repo}/git/trees/${sha}?recursive=1"
  curl -sSf \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${api_url}" \
  | jq -r --arg prefix "packages/${dir}/migrations/" '.tree[]?.path | select(startswith($prefix))' \
  | sort
}

check_pending() {
  local sha="$1"
  local dir="$2"
  local last="$3"
  local repo="$4"

  files=()
  while IFS= read -r line; do
    files+=("${line}")
  done < <(list_remote_migrations "${repo}" "${sha}" "${dir}")

  if ((${#files[@]} == 0)); then
    echo "warning: no migrations found at ${dir} for sha ${sha}" >&2
    return
  fi

  if [[ -z "${last}" || "${last}" == "null" ]]; then
    has_pending=true
    return
  fi

  for f in "${files[@]}"; do
    base=$(basename "${f}")
    if [[ "${base}" > "${last}" ]]; then
      has_pending=true
      return
    fi
  done
}

check_pending "${catalog_sha}" "catalog-and-users-service" "${catalog_last}" "${catalog_repo}"
check_pending "${broker_sha}" "lsports-broker" "${broker_last}" "${broker_repo}"

echo "migrations_needed=${has_pending}"

if [[ "${has_pending}" == "true" ]]; then
  exit 0
else
  exit 1
fi
