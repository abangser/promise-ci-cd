#!/usr/bin/env bash
# Adds the module's promise.yaml to platform-api/kustomization.yaml if not already listed.
# Creates the kustomization.yaml if this is the first module to be registered.
# Usage: register-module.sh <MODULE>
set -euo pipefail

MODULE="$1"
[[ -z "${MODULE:-}" ]] && { echo "Error: MODULE is not set" >&2; exit 1; }
ENTRY="${MODULE}-promise/promise.yaml"
KUSTOMIZATION="platform-api/kustomization.yaml"

if [[ ! -f "${KUSTOMIZATION}" ]]; then
  mkdir -p platform-api
  cat > "${KUSTOMIZATION}" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
EOF
  echo "Created ${KUSTOMIZATION}"
fi

if ! yq '.resources[]' "${KUSTOMIZATION}" | grep -qF "${ENTRY}"; then
  yq -i ".resources += [\"${ENTRY}\"]" "${KUSTOMIZATION}"
  echo "Registered ${ENTRY} in ${KUSTOMIZATION}"
else
  echo "${ENTRY} already registered"
fi
