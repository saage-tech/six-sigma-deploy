#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:?environment required}"
OUTPUT_PATH="${2:?output path required}"
FILE_PATH="${3:-versions.json}"

service="publicmq"
deploy_type=$(jq -r '.deploy_type // "simple"' "${FILE_PATH}")

case "${deploy_type}" in
  simple)
    stages='["ensure-deployment"]'
    ;;
  with-database-migration)
    stages='["scale-down-catalog-services","apply-database-migration","ensure-deployment"]'
    ;;
  with-chain-upgrade)
    stages='["launch-green-environment","reconfigure-websocket-endpoint","execute-upgrader-component","verify-green-environment","update-blue-environment","remove-green-environment","update-dependent-services","update-chain-history-documentation","ensure-deployment"]'
    ;;
  with-database-migration-and-chain-upgrade)
    stages='["scale-down-catalog-services","apply-database-migration","launch-green-environment","reconfigure-websocket-endpoint","execute-upgrader-component","verify-green-environment","update-blue-environment","remove-green-environment","update-dependent-services","update-chain-history-documentation","ensure-deployment"]'
    ;;
  *)
    echo "Unknown deploy type '${deploy_type}', defaulting to simple"
    stages='["ensure-deployment"]'
    ;;
esac

{
  echo "service=${service}"
  echo "deploy_type=${deploy_type}"
  echo "stages=${stages}"
} >> "${OUTPUT_PATH}"

echo "[${ENV_NAME}] Service ${service} deploy_type=${deploy_type}; stages=${stages}"
