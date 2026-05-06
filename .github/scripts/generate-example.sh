#!/usr/bin/env bash
# Enriches the CLI-generated example-resource.yaml in place, adds namespace,
# and populates all spec fields from CRD schema defaults.
# Usage: generate-example.sh <MODULE>
set -euo pipefail

MODULE="$1"
# shellcheck source=.github/scripts/common.sh
source "$(dirname "$0")/common.sh"

EXAMPLE="${PROMISE_DIR}/example-resource.yaml"
yq -i '.metadata.namespace = "default"' "${EXAMPLE}"

SCHEMA_BASE=".spec.api.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties"
while IFS= read -r PROP; do
  TYPE=$(yq "${SCHEMA_BASE}.\"${PROP}\".type" "${PROMISE}")
  DEFAULT=$(yq "${SCHEMA_BASE}.\"${PROP}\".default" "${PROMISE}")
  if [[ "${TYPE}" == "string" && ( -z "${DEFAULT}" || "${DEFAULT}" == "null" ) ]]; then
    yq -i ".spec.\"${PROP}\" = \"example-${MODULE}\"" "${EXAMPLE}"
  elif [[ "${TYPE}" == "string" ]]; then
    yq -i ".spec.\"${PROP}\" = \"${DEFAULT}\"" "${EXAMPLE}"
  else
    yq -i ".spec.\"${PROP}\" = ${DEFAULT}" "${EXAMPLE}"
  fi
done < <(yq "${SCHEMA_BASE} | keys | .[]" "${PROMISE}")

echo "Generated example: ${EXAMPLE} (kept alongside promise)"
