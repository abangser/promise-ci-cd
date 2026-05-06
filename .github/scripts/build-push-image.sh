#!/usr/bin/env bash
# Builds and pushes the promise dependencies image to ghcr.io, then updates
# the image reference in the generated promise.yaml.
# Usage: build-push-image.sh <MODULE> <VERSION>
set -euo pipefail

MODULE="$1"
VERSION="$2"
[[ -z "${VERSION:-}" ]] && { echo "Error: VERSION is not set" >&2; exit 1; }
# shellcheck source=.github/scripts/common.sh
source "$(dirname "$0")/common.sh"

DEPS_DIR="${PROMISE_DIR}/workflows/promise/configure/dependencies/add-tf-dependencies"
REPO="${GITHUB_REPOSITORY#*/}"
IMAGE="ghcr.io/${GITHUB_REPOSITORY_OWNER}/${REPO}-${MODULE}-dependencies:${VERSION}"

if ! grep -q "org.opencontainers.image.source" "${DEPS_DIR}/Dockerfile"; then
  echo "LABEL org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}" >> "${DEPS_DIR}/Dockerfile"
fi

docker build -t "${IMAGE}" "${DEPS_DIR}"
docker push "${IMAGE}"
yq -i ".spec.workflows.promise.configure[0].spec.containers[0].image = \"${IMAGE}\"" "${PROMISE}"
echo "Built and pushed ${IMAGE}"

"$(dirname "$0")/set-package-visibility.sh" "${REPO}-${MODULE}-dependencies"
