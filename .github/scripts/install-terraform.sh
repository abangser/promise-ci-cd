#!/usr/bin/env bash
set -euo pipefail

VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['current_version'])")
curl -sL "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip" \
  -o /tmp/terraform.zip
sudo unzip -q /tmp/terraform.zip -d /usr/local/bin terraform
