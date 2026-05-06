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
