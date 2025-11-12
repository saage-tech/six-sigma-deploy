#!/usr/bin/env bash
set -euo pipefail

STAGES_JSON="${1:?stages json required}"
OUTPUT_PATH="${2:?output path required}"

stages="${STAGES_JSON:-[]}"

has_stage() {
  local stage="$1"
  if echo "${stages}" | jq -e --arg stage "${stage}" 'index($stage) != null' >/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

echo "stage_scale_down_catalog_services=$(has_stage "scale-down-catalog-services")" >> "${OUTPUT_PATH}"
echo "stage_apply_database_migration=$(has_stage "apply-database-migration")" >> "${OUTPUT_PATH}"
echo "stage_launch_green_environment=$(has_stage "launch-green-environment")" >> "${OUTPUT_PATH}"
echo "stage_reconfigure_websocket_endpoint=$(has_stage "reconfigure-websocket-endpoint")" >> "${OUTPUT_PATH}"
echo "stage_execute_upgrader_component=$(has_stage "execute-upgrader-component")" >> "${OUTPUT_PATH}"
echo "stage_verify_green_environment=$(has_stage "verify-green-environment")" >> "${OUTPUT_PATH}"
echo "stage_update_blue_environment=$(has_stage "update-blue-environment")" >> "${OUTPUT_PATH}"
echo "stage_remove_green_environment=$(has_stage "remove-green-environment")" >> "${OUTPUT_PATH}"
echo "stage_update_dependent_services=$(has_stage "update-dependent-services")" >> "${OUTPUT_PATH}"
echo "stage_update_chain_history_documentation=$(has_stage "update-chain-history-documentation")" >> "${OUTPUT_PATH}"
echo "stage_ensure_deployment=$(has_stage "ensure-deployment")" >> "${OUTPUT_PATH}"
