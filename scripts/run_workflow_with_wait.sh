#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions does not allow expressions inside the `uses:` value for reusable
# workflows (owner/repo/path@ref must be a literal string), but our workflow
# metadata is dynamic per image. We invoke the workflow via the GitHub CLI and
# watch the resulting run to keep the calling job synchronous.

OWNER="${OWNER:?OWNER required}"
REPO="${1:?repository required}"
WORKFLOW_FILE="${2:?workflow file required}"
REF="${3:?ref required}"
WORKFLOW_INPUTS_JSON="${4:-}"
TOKEN="${TOKEN:?token required}"

export GH_TOKEN="${TOKEN}"

echo "Running ${OWNER}/${REPO} workflow ${WORKFLOW_FILE} @ ${REF} (waiting for completion)"

workflow_input_args=()

if [[ -n "${WORKFLOW_INPUTS_JSON}" && "${WORKFLOW_INPUTS_JSON}" != "null" ]]; then
  if ! echo "${WORKFLOW_INPUTS_JSON}" | jq -e 'type == "object"' >/dev/null; then
    echo "WORKFLOW_INPUTS_JSON must be a JSON object. Received: ${WORKFLOW_INPUTS_JSON}" >&2
    exit 1
  fi

  mapfile -t workflow_inputs < <(echo "${WORKFLOW_INPUTS_JSON}" | jq -r 'to_entries[] | "\(.key)=\(.value // "")"')

  for input in "${workflow_inputs[@]}"; do
    workflow_input_args+=("-f" "${input}")
  done
fi

workflow_cmd=(gh workflow run "${WORKFLOW_FILE}" --repo "${OWNER}/${REPO}" --ref "${REF}")
workflow_cmd+=("${workflow_input_args[@]}")

"${workflow_cmd[@]}"

sleep 5

run_info=$(gh run list \
  --repo "${OWNER}/${REPO}" \
  --workflow "${WORKFLOW_FILE}" \
  --branch "${REF}" \
  --limit 1 \
  --json databaseId,headSha \
  -q '.[0]')

run_id=$(echo "${run_info}" | jq -r '.databaseId')
head_sha=$(echo "${run_info}" | jq -r '.headSha')

if [[ -z "${run_id}" ]]; then
  echo "Unable to determine workflow run ID for ${OWNER}/${REPO} ${WORKFLOW_FILE} @ ${REF}"
  exit 1
fi

echo "Tracking run ${run_id} (sha: ${head_sha})"

while true; do
  status=$(gh run view "${run_id}" \
    --repo "${OWNER}/${REPO}" \
    --json status \
    -q '.status')

  if [[ "${status}" == "completed" ]]; then
    conclusion=$(gh run view "${run_id}" \
      --repo "${OWNER}/${REPO}" \
      --json conclusion \
      -q '.conclusion')

    if [[ "${conclusion}" == "success" ]]; then
      echo "Workflow run ${run_id} completed successfully."
      exit 0
    else
      echo "Workflow run ${run_id} completed with status: ${conclusion}"
      echo "Last 200 log lines:"
      gh run view "${run_id}" --repo "${OWNER}/${REPO}" --log --exit-status | tail -n 200
      exit 1
    fi
  fi

  echo "Workflow run ${run_id} status: ${status} (waiting...)"
  sleep 15
done
