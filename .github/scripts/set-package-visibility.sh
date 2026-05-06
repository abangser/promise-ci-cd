#!/usr/bin/env bash
# Attempts to set a ghcr.io package to public after push.
# GHCR packages are private by default and the REST API PATCH endpoint for
# changing package visibility is unreliable — it returns 404 even with correct
# scopes and a valid package. If the API call fails, this script prints the
# GitHub UI URL so the user can change visibility manually.
# Usage: set-package-visibility.sh <PACKAGE_NAME>
set -euo pipefail

PACKAGE_NAME="$1"
[[ -z "${PACKAGE_NAME:-}" ]] && { echo "Error: PACKAGE_NAME is not set" >&2; exit 1; }

OWNER="${GITHUB_REPOSITORY_OWNER}"
if gh api "users/${OWNER}" --jq '.type' 2>/dev/null | grep -q "Organization"; then
  PKG_URL="orgs/${OWNER}/packages/container/${PACKAGE_NAME}"
  SETTINGS_URL="https://github.com/orgs/${OWNER}/packages/container/${PACKAGE_NAME}/settings"
else
  PKG_URL="user/packages/container/${PACKAGE_NAME}"
  SETTINGS_URL="https://github.com/users/${OWNER}/packages/container/${PACKAGE_NAME}/settings"
fi

if gh api --method PATCH "${PKG_URL}" -f visibility=public 2>/dev/null; then
  echo "Package ${PACKAGE_NAME} set to public"
else
  echo "Warning: could not set ${PACKAGE_NAME} to public via API." >&2
  echo "Set it manually at: ${SETTINGS_URL}" >&2
fi
