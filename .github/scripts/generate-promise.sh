#!/usr/bin/env bash
# Generates a Kratix Promise from a Terraform module.
# Versioning is handled separately by bump-version.sh after all post-generation
# injections have run, so the version diff reflects the final promise.
# Usage: generate-promise.sh <MODULE>
set -euo pipefail

MODULE="$1"
# shellcheck source=.github/scripts/common.sh
source "$(dirname "$0")/common.sh"

KIND=$(echo "${MODULE}" \
  | awk -F'-' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1' OFS='')

echo "Kind: ${KIND}, Promise dir: ${PROMISE_DIR}" >&2

[[ -f "tf-modules/${MODULE}/variables.tf" ]] \
  || { echo "Error: tf-modules/${MODULE}/variables.tf not found" >&2; exit 1; }

mkdir -p "${PROMISE_DIR}"
rm -f "${PROMISE}"
kratix init tf-module-promise "${MODULE}" \
  --module-source "github.com/${GITHUB_REPOSITORY}//tf-modules/${MODULE}?ref=main" \
  --group example.kratix.io \
  --kind "${KIND}" \
  --dir "${PROMISE_DIR}" >&2

# Embed a hash of all Terraform files so bump-version.sh detects changes to
# implementation files (e.g. main.tf) that don't alter the variables-derived
# promise structure but do produce a different dependencies image.
TF_HASH=$(find "tf-modules/${MODULE}" -type f | sort | xargs sha256sum | sha256sum | cut -c1-12)
yq -i ".metadata.annotations.\"promise.kratix.io/tf-hash\" = \"${TF_HASH}\"" "${PROMISE}"
echo "Terraform module hash: ${TF_HASH}" >&2

# kratix init always writes a generic marketplace image as the dependencies
# container. build-push-image.sh later replaces it with the versioned built
# image, but bump-version.sh runs *before* that step. Pre-seeding the image
# to match what is currently on generated-promises means the comparison sees
# final-vs-final rather than default-vs-built, eliminating a spurious diff
# that would otherwise bump the version on every single run.
BRANCH_PROMISE="${PROMISE#platform-api/}"
if git show "origin/generated-promises:${BRANCH_PROMISE}" &>/dev/null; then
  PREV_VERSION=$(git show "origin/generated-promises:${BRANCH_PROMISE}" \
    | yq ".metadata.annotations.\"${ANNOTATION}\" // \"\"")
  if [[ -n "${PREV_VERSION}" ]]; then
    OWNER="${GITHUB_REPOSITORY_OWNER:-${GITHUB_REPOSITORY%%/*}}"
    REPO_NAME="${GITHUB_REPOSITORY#*/}"
    PREV_IMAGE="ghcr.io/${OWNER}/${REPO_NAME}-${MODULE}-dependencies:${PREV_VERSION}"
    yq -i ".spec.workflows.promise.configure[0].spec.containers[0].image = \"${PREV_IMAGE}\"" "${PROMISE}"
    echo "Pre-seeded dependencies image: ${PREV_IMAGE}" >&2
  fi
fi
