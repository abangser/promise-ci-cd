#!/usr/bin/env bash
# Injects the github-sign-off approval gate as the first container in the
# resource.configure pipeline, before the kratix-generated terraform-generate step.
#
# The sign-off image opens a GitHub Issue from the ResourceRequest and holds
# the pipeline until a human closes it — approved ("completed") or rejected
# ("not planned"). This gives platform engineers a place to encode organisational
# approval rules without touching the Terraform module or the developer's request.
#
# This step is injected here rather than committed on the generated-promises branch
# so it survives CI regeneration: kratix init always produces a clean promise from
# variables.tf, and this script adds the gate back on every run.
#
# Usage: inject-sign-off.sh <MODULE>
set -euo pipefail

MODULE="$1"
# shellcheck source=.github/scripts/common.sh
source "$(dirname "$0")/common.sh"

SIGN_OFF_YAML=$(mktemp --suffix=.yaml)
cat > "${SIGN_OFF_YAML}" << EOF
name: github-sign-off
image: ghcr.io/syntasso/kratix-marketplace/pipeline-github-sign-off-image:v0.2.0
command: ["create-and-wait-for-approval"]
env:
  - name: GITHUB_REPOSITORY
    value: "${GITHUB_REPOSITORY}"
  - name: GITHUB_TOKEN
    valueFrom:
      secretKeyRef:
        name: github-token
        key: token
  - name: RETRY_AFTER
    value: "90s"
EOF

yq -i "
  .spec.workflows.resource.configure[0].spec.containers =
    [load(\"${SIGN_OFF_YAML}\")] +
    .spec.workflows.resource.configure[0].spec.containers
" "${PROMISE}"

rm -f "${SIGN_OFF_YAML}"
echo "Injected github-sign-off approval gate into ${PROMISE}"
