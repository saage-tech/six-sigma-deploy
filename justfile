set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set export := true

# Exported defaults (can be overridden)
ENV_NAME := env_var_or_default("ENV_NAME", "devnet")
OWNER := env_var_or_default("OWNER", "saage-tech")
VERSIONS_PATH := env_var_or_default("VERSIONS_PATH", "versions.json")
token_override := env_var_or_default("TOKEN", "")
TOKEN := if token_override != "" { token_override } else { `gh auth token || true` }
SKIP_REMOTE := env_var_or_default("SKIP_REMOTE", "false")
REGISTRY:="ghcr.io/saage-tech"

# Update versions.json image refs (env vars above are exported)
update-versions:
	scripts/resolve_image_refs.sh
	scripts/get_kolme_code_version.sh

persist-metadata:
	scripts/persist_metadata.sh

# Build/publish an image by key (uses SKIP_REMOTE to suppress remote dispatch)
build-and-publish-image IMAGE_KEY:
	IMAGE_KEY={{IMAGE_KEY}} scripts/build_and_publish_image.sh

# Set release_type override from RELEASE_TYPE_INPUT env (no-op if empty)
set-release-type RELEASE_TYPE:
	RELEASE_TYPE_INPUT="{{RELEASE_TYPE}}" \
	VERSIONS_PATH="${VERSIONS_PATH}" \
	bash scripts/set_release_type.sh "{{RELEASE_TYPE}}"

# Emit release_type to a file (or stdout if TO_FILE omitted)
get-release-type:
	VERSIONS_PATH="${VERSIONS_PATH}" \
	bash scripts/get_release_type.sh

# Check if a specific image (by key in versions.json) exists in GHCR
check-image IMAGE_KEY:
	IMAGE_KEY={{IMAGE_KEY}} OUTPUT_PATH=/dev/stdout scripts/check_image_exists.sh

# Emit image keys as JSON array (for matrix consumption)
list-images-json:
	jq -c '.images | keys' "${VERSIONS_PATH}"

# List all image keys from versions.json
list-images:
	jq -r '.images | keys[]' "${VERSIONS_PATH}"

# Build/publish all images listed in versions.json via the just task
build-all-images:
	for img in $(just list-images); do \
		just build-and-publish-image "$img" || exit $$?; \
	done

# Build/publish all images in parallel (one per key)
build-all-images-parallel:
    just list-images | xargs -n1 -P0 just build-and-publish-image

# Retrieve Kolme CODE_VERSION at pinned revision and update versions.json
get-kolme-code-version:
	scripts/get_kolme_code_version.sh

# Scale down catalog services for an environment (runs v2_infra_apply.sh)
scale-down-catalog-services:
	scripts/scale_down_catalog_services.sh
	
# Apply database migration for catalog/broker (runs v2_infra_apply.sh)
apply-database-migration:
	bash scripts/apply_database_migration.sh

# Update last_applied migration markers from GitHub
update-last-applied-migrations:
	bash scripts/update_last_applied_migrations.sh

# Launch green environment (runs v2_infra_apply.sh)
launch-green-environment:
	CODE_VERSION=`just get-kolme-code-version` \
	scripts/launch_green_environment.sh

# Run upgrader component when chain != green code_version
run-upgrader-component:
	bash scripts/run_upgrader_component.sh

# Update blue environment when versions align
update-blue-environment:
	bash scripts/update_blue_environment.sh

# Remove green environment when chain is synced
remove-green-environment:
	bash scripts/remove_green_environment.sh

# Ensure deployment (terraform apply model)
ensure-deployment:
	bash scripts/ensure_deploy.sh

# Wait until chain API code/chain version matches target (from versions.json)
wait-chain-version-matches:
	TARGET_CODE_VERSION=`just get-kolme-code-version` \
	API_URL_KEY="chain_api_url" \
	bash scripts/wait_for_version_to_match.sh

# Wait until chain API code_version matches target (alias)
wait-code-version-matches:
	TARGET_CODE_VERSION=`just get-kolme-code-version` \
	API_URL_KEY="chain_api_url" \
	bash scripts/wait_for_version_to_match.sh

# Wait until green API code/chain version matches target (from versions.json)
wait-green-chain-version-matches:
	TARGET_CODE_VERSION=`just get-kolme-code-version` \
	API_URL_KEY="green_api_url" \
	bash scripts/wait_for_version_to_match.sh

# Wait until green API code_version matches target (alias)
wait-green-code-version-matches:
	TARGET_CODE_VERSION=`just get-kolme-code-version` \
	API_URL_KEY="green_api_url" \
	bash scripts/wait_for_version_to_match.sh
# Wait for green endpoint to be removed
wait-green-termination:
	bash scripts/ensure_green_removed.sh


deploy: scale-down-catalog-services apply-database-migration update-last-applied-migrations launch-green-environment run-upgrader-component update-blue-environment remove-green-environment ensure-deployment
