#!/usr/bin/env bash
set -euo pipefail

curl -sL "https://github.com/syntasso/kratix-cli/releases/latest/download/kratix-cli_Linux_x86_64.tar.gz" \
  | tar -xz -C /tmp kratix
sudo mv /tmp/kratix /usr/local/bin/kratix
