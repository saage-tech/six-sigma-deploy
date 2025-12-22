# Deployment Orchestration

This repository holds the CI/CD wiring that publishes service images and rolls out our environments. It is intentionally light on implementation details; internal developers can use the notes below as a quick-start.

## How it works
- `versions.json` is the single source of truth for what to ship (image keys, refs, and target environments).
- The GitHub Actions workflow builds/publishes images to our container registry and then deploys environments in order (devnet → testnet → mainnet).
- Image builds run in parallel via a matrix; each image entry in `versions.json` drives one build.
- Environments are protected; only authorized reviewers can promote deployments.

## Day-to-day usage
- **Targeted change (single image):** edit `versions.json` to bump the image revision you want, open a PR to `main`, and merge after review. The pipeline will build/publish that image and deploy in order.
- **Recommended (refresh everything):** trigger the workflow manually with `auto_update_images=true` to pull the latest revisions for all images, then merge the generated PR or re-run with the updated metadata.

## Notes
- You can list all image keys with `just list-images` and build one with `just build-and-publish-image <key>`.
- Deployment behavior (staging order, health checks, etc.) lives in the composite action under `.github/actions/deploy-environment`.
- Access to registry credentials, app tokens, and protected environments is limited to the internal deployment group. Reach out to the platform team if you need access or approvals.
