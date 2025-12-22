#!/usr/bin/env bash
set -euo pipefail

# Ensure Deploy - thin wrapper to dispatch terraform apply for all runtime services via v2_infra_apply.sh.
# Behavior: sets defaults for service list/action/targets/extra locals and delegates to v2_infra_apply.sh.
# Honors SKIP_REMOTE/DRY_RUN inside v2_infra_apply.sh.
#
# Required env:
#   ENV_NAME - target environment
#   OWNER    - GitHub org/user for the infra repo
#   TOKEN    - token with workflow dispatch permissions
# Optional env (defaults shown):
#   VERSIONS_PATH   (versions.json)
#   WORKFLOW_REPO   (v2-infrastructure)
#   WORKFLOW_FILE   (.github/workflows/terraform-apply.yml)
#   WORKFLOW_REF    (main)
#   ACTION          ("ensure deploy")
#   JUST_TARGETS    ("plan apply")
#   SERVICE_LIST    (comma-separated; defaults to all runtime services)
#   EXTRA_LOCALS    (defaults to catalog_and_broker_task_count=1)
#   SKIP_REMOTE     (false)
#   DRY_RUN         (false)

ENV_NAME="${ENV_NAME:-${1-}}"
if [[ -z "${ENV_NAME}" ]]; then
  echo "ENV_NAME is required (provide via environment variable)" >&2
  exit 1
fi

OWNER="${OWNER:?OWNER is required}"
TOKEN="${TOKEN:?TOKEN is required}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"

ACTION="ensure deploy"
JUST_TARGETS="plan apply"

# Fixed service list and extra locals (not overridden by env)
SERVICE_LIST="bots,app_api_server,back_office,indexer,catalog,lsports_ingester,lsports_processor,lsports_broker,odds,kolme_processor,kolme_listener,kolme_api_server,kolme_submitter,kolme_approver,kolme_archiver"
EXTRA_LOCALS="catalog_and_broker_task_count=1"

export SERVICE_LIST ACTION JUST_TARGETS EXTRA_LOCALS ENV_NAME OWNER TOKEN
export SKIP_REMOTE="${SKIP_REMOTE:-false}"
export DRY_RUN="${DRY_RUN:-false}"

bash scripts/v2_infra_apply.sh
