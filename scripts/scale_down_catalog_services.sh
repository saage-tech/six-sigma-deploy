#!/usr/bin/env bash
set -euo pipefail

# Scale down catalog services only when DB migrations are pending, otherwise exit cleanly.
# Runs only if: pending migrations exist for catalog/broker (detected via check_pending_migrations.sh).
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

echo "Checking pending migrations for ${ENV_NAME}..."
if ! ENV_NAME="${ENV_NAME}" VERSIONS_PATH="${VERSIONS_PATH}" OWNER="${OWNER}" TOKEN="${TOKEN}" scripts/check_pending_migrations.sh; then
  echo "No pending migrations for ${ENV_NAME}; skipping scale down."
  exit 0
fi

echo "Pending migrations detected for ${ENV_NAME}; scaling down catalog services."
SERVICE_LIST="catalog_db_image,broker_db_image" \
ACTION="scale down catalog services" \
JUST_TARGETS="init plan apply" \
EXTRA_LOCALS=$'catalog_and_broker_task_count=0' \
ENV_NAME="${ENV_NAME}" \
OWNER="${OWNER}" \
TOKEN="${TOKEN}" \
VERSIONS_PATH="${VERSIONS_PATH}" \
SKIP_REMOTE="${SKIP_REMOTE}" \
bash scripts/v2_infra_apply.sh
