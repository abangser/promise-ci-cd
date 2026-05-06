#!/usr/bin/env bash
# Shared constants sourced by pipeline scripts.
# Requires MODULE to be set before sourcing.
[[ -z "${MODULE:-}" ]] && { echo "Error: MODULE is not set" >&2; exit 1; }

# GitHub Actions sets GITHUB_REPOSITORY automatically. For local runs,
# derive it from the git remote so scripts work in both contexts.
if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  GITHUB_REPOSITORY=$(git remote get-url origin \
    | sed -E 's|.*github\.com[:/]||; s|\.git$||')
  export GITHUB_REPOSITORY
fi

PROMISE_DIR="platform-api/${MODULE}-promise"
PROMISE="${PROMISE_DIR}/promise.yaml"
ANNOTATION="promise.kratix.io/version"
