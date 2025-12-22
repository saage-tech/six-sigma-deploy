#!/usr/bin/env bash
set -euo pipefail

# Dispatch the v2-infrastructure terraform apply workflow with service tag locals
# resolved from versions.json. Designed to be driven entirely by env vars so the
# caller can remain generic.
#
# Required env:
#   ENV_NAME   - deployment environment (devnet|testnet|mainnet, etc.)
#   OWNER      - GitHub org/user that owns the target workflow repository
#   TOKEN      - GitHub token with permissions to dispatch the workflow
#   SERVICE_LIST - comma-separated services; each entry may be "svc" or "svc:locals_key"
#
# Optional env:
#   VERSIONS_PATH          - path to versions.json (default: versions.json)
#   WORKFLOW_REPO          - repo housing the infra workflow (default: v2-infrastructure)
#   WORKFLOW_FILE          - workflow file path (default: .github/workflows/terraform-apply.yml)
#   WORKFLOW_REF           - ref for the infra workflow (default: main)
#   ACTION                 - description string for the workflow (default: "ensure deploy")
#   JUST_TARGETS           - terraform steps to run (default: "plan apply")
#   SERVICE_INPUT_KEYS_JSON- JSON map of service -> locals key (overrides defaults)
#   EXTRA_INPUTS_JSON      - JSON object merged into workflow inputs (optional)
#   EXTRA_LOCALS           - newline-delimited key=value pairs merged into locals_json
#   DRY_RUN                - if "true", print composed inputs and exit
#   SKIP_REMOTE            - if "true", skip dispatch entirely
#
# Defaults: publicmq -> rust_publicmq_tag (locals key) if no override is provided.

ENV_NAME="${ENV_NAME:-}"
OWNER="${OWNER:-}"
TOKEN="${TOKEN:-}"
VERSIONS_PATH="${VERSIONS_PATH:-versions.json}"
WORKFLOW_REPO="${WORKFLOW_REPO:-v2-infrastructure}"
WORKFLOW_FILE="${WORKFLOW_FILE:-.github/workflows/terraform-apply.yml}"
WORKFLOW_REF="${WORKFLOW_REF:-main}"
ACTION="${ACTION:-ensure deploy}"
JUST_TARGETS="${JUST_TARGETS:-plan apply}"
SERVICE_LIST="${SERVICE_LIST:-}"
SERVICE_INPUT_KEYS_JSON="${SERVICE_INPUT_KEYS_JSON:-}"
EXTRA_INPUTS_JSON="${EXTRA_INPUTS_JSON:-}"
EXTRA_LOCALS="${EXTRA_LOCALS:-}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_REMOTE="${SKIP_REMOTE:-false}"

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

if [[ -z "${SERVICE_LIST}" ]]; then
  echo "SERVICE_LIST is required (comma-separated list of service or service:locals_key)" >&2
  exit 1
fi

get_default_locals_key() {
  case "$1" in
    publicmq) echo "rust_publicmq_tag" ;;
    *) echo "" ;;
  esac
}

get_override_locals_key() {
  local svc="$1"
  if [[ -z "${SERVICE_INPUT_KEYS_JSON}" || "${SERVICE_INPUT_KEYS_JSON}" == "null" ]]; then
    return
  fi
  echo "${SERVICE_INPUT_KEYS_JSON}" | jq -r --arg svc "${svc}" '.[$svc] // empty'
}

locals_json='{}'
tmp_files=()
cleanup() {
  if ((${#tmp_files[@]} > 0)); then
    rm -f "${tmp_files[@]}"
  fi
}
trap cleanup EXIT
IFS=',' read -ra service_entries <<< "${SERVICE_LIST}"

for raw_entry in "${service_entries[@]}"; do
  entry="${raw_entry//[[:space:]]/}"
  [[ -z "${entry}" ]] && continue

  service="${entry%%:*}"
  locals_key=""

  # Priority: explicit mapping in SERVICE_LIST (svc:locals), override JSON, tag_name in versions.json, default map, fallback to service name
  if [[ "${entry}" == *:* ]]; then
    locals_key="${entry#*:}"
  else
    override_key=$(get_override_locals_key "${service}")
    if [[ -n "${override_key}" ]]; then
      locals_key="${override_key}"
    else
      locals_key=$(jq -r --arg svc "${service}" '.services[$svc].tag_name // empty' "${VERSIONS_PATH}")
      if [[ -z "${locals_key}" ]]; then
        default_key=$(get_default_locals_key "${service}")
        if [[ -n "${default_key}" ]]; then
          locals_key="${default_key}"
        else
          locals_key="${service}"
        fi
      fi
    fi
  fi

  image_name=$(jq -r --arg svc "${service}" '.services[$svc].image // empty' "${VERSIONS_PATH}")
  if [[ -z "${image_name}" || "${image_name}" == "null" ]]; then
    echo "Unable to find image for service '${service}' in ${VERSIONS_PATH}" >&2
    exit 1
  fi

  metadata_tmp=$(mktemp)
  tmp_files+=("${metadata_tmp}")
  scripts/get_image_metadata.sh "${image_name}" "${metadata_tmp}" "${VERSIONS_PATH}"

  unset revision_sha
  # shellcheck disable=SC1090
  source "${metadata_tmp}"
  rm -f "${metadata_tmp}"
  tmp_files=("${tmp_files[@]/${metadata_tmp}/}")

  if [[ -z "${revision_sha:-}" ]]; then
    echo "revision_sha missing for image '${image_name}' (service '${service}')" >&2
    exit 1
  fi

  locals_json=$(echo "${locals_json}" | jq --arg key "${locals_key}" --arg tag "${revision_sha}" '. + {($key): $tag}')
done

# Merge extra locals from newline-delimited key=value pairs if provided
if [[ -n "${EXTRA_LOCALS}" ]]; then
  extra_locals_json=$(
    python3 - <<'PY'
import json, os
raw = os.environ.get("EXTRA_LOCALS", "")
updates = {}
for line in raw.splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if "=" not in line:
        raise SystemExit(f"EXTRA_LOCALS entry missing '=': {line}")
    key, val = line.split("=", 1)
    key = key.strip()
    val = val.strip()
    if not key:
        raise SystemExit("EXTRA_LOCALS entry has empty key")
    try:
        parsed = json.loads(val)
    except json.JSONDecodeError:
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            parsed = val[1:-1]
        else:
            parsed = val
    updates[key] = parsed
print(json.dumps(updates))
PY
  )
  locals_json=$(jq -n --argjson base "${locals_json}" --argjson extra "${extra_locals_json}" '$base + $extra')
fi

workflow_inputs=$(jq -n \
  --arg environment "${ENV_NAME}" \
  --argjson locals_json "${locals_json}" \
  --arg action "${ACTION}" \
  --arg just_targets "${JUST_TARGETS}" \
  '{environment: $environment, locals_json: $locals_json, action: $action, just_targets: $just_targets}')

if [[ -n "${EXTRA_INPUTS_JSON}" && "${EXTRA_INPUTS_JSON}" != "null" ]]; then
  workflow_inputs=$(jq -n \
    --argjson base "${workflow_inputs}" \
    --argjson extra "${EXTRA_INPUTS_JSON}" \
    '$base + $extra')
fi

echo "Infra apply inputs: $(jq -c <<< "${workflow_inputs}")"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "DRY_RUN=true; exiting before dispatch"
  exit 0
fi

if [[ "${SKIP_REMOTE}" == "true" ]]; then
  echo "SKIP_REMOTE=true; would dispatch ${WORKFLOW_REPO}:${WORKFLOW_FILE} @ ${WORKFLOW_REF} with inputs above; skipping dispatch."
  exit 0
fi

export OWNER
export TOKEN

scripts/run_workflow_with_wait.sh \
  "${WORKFLOW_REPO}" \
  "${WORKFLOW_FILE}" \
  "${WORKFLOW_REF}" \
  "${workflow_inputs}"
