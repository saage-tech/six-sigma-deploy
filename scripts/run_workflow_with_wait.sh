#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions does not allow expressions inside the `uses:` value for reusable
# workflows (owner/repo/path@ref must be a literal string), but our workflow
# metadata is dynamic per image. We invoke `gh workflow run --wait` instead so
# we can supply the repo, workflow file, and ref at runtime while still waiting
# for completion.

OWNER="${OWNER:?OWNER required}"
REPO="${1:?repository required}"
WORKFLOW_FILE="${2:?workflow file required}"
REF="${3:?ref required}"
TOKEN="${TOKEN:?token required}"

export GH_TOKEN="${TOKEN}"

echo "Running ${OWNER}/${REPO} workflow ${WORKFLOW_FILE} @ ${REF} (waiting for completion)"

gh workflow run "${WORKFLOW_FILE}" \
  --repo "${OWNER}/${REPO}" \
  --ref "${REF}" \
  --wait
