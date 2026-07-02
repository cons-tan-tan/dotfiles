#!/usr/bin/env bash
set -euo pipefail

: "${DARWIN_HOSTNAME:?DARWIN_HOSTNAME must be set}"

echo "Building and switching to darwin configuration..."
sudo nix run nix-darwin -- switch --flake ".#${DARWIN_HOSTNAME}"
