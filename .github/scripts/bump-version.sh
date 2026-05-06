#!/usr/bin/env bash
# Compares the final Promise against the committed version on generated-promises,
# bumps the patch version if the content has changed, and prints the resolved
# version to stdout.
#
# Called after all post-generation injections (e.g. inject-sign-off.sh) so the
# diff reflects the complete, final Promise. This means injected stages are
# visible in the diff when first introduced, and the version annotation
# accurately describes the full Promise a cluster will receive.
#
# Usage: bump-version.sh <MODULE>
set -euo pipefail

MODULE="$1"
# shellcheck source=.github/scripts/common.sh
source "$(dirname "$0")/common.sh"

# commit-output.sh strips the platform-api/ prefix when publishing to
# generated-promises, so look up files without that prefix.
BRANCH_PROMISE="${PROMISE#platform-api/}"

if git show "origin/generated-promises:${BRANCH_PROMISE}" &>/dev/null; then
  CURRENT=$(git show "origin/generated-promises:${BRANCH_PROMISE}" \
    | yq ".metadata.annotations.\"${ANNOTATION}\" // \"0.1.0\"")

  # Strip only the version annotation before diffing — it changes on every bump
  # and would always appear as a diff regardless of actual content changes.
  git show "origin/generated-promises:${BRANCH_PROMISE}" \
    | yq "del(.metadata.annotations.\"${ANNOTATION}\")" \
    > /tmp/committed.yaml
  yq "del(.metadata.annotations.\"${ANNOTATION}\")" \
    "${PROMISE}" > /tmp/generated.yaml

  if diff -q /tmp/committed.yaml /tmp/generated.yaml > /dev/null 2>&1; then
    echo "No changes — keeping version ${CURRENT}" >&2
    NEW_VERSION="${CURRENT}"
  else
    PATCH=$(echo "${CURRENT}" | cut -d. -f3)
    NEW_VERSION="$(echo "${CURRENT}" | cut -d. -f1-2).$((PATCH + 1))"
    echo "Promise changed — bumping ${CURRENT} → ${NEW_VERSION}" >&2
    diff /tmp/committed.yaml /tmp/generated.yaml >&2 || true
  fi
else
  NEW_VERSION="0.1.0"
  echo "New Promise — setting initial version ${NEW_VERSION}" >&2
fi

yq -i ".metadata.annotations.\"${ANNOTATION}\" = \"${NEW_VERSION}\"" "${PROMISE}"
echo "${NEW_VERSION}"
