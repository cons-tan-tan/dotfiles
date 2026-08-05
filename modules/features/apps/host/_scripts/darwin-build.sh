#!/usr/bin/env bash
set -euo pipefail

: "${DARWIN_HOSTNAME:?DARWIN_HOSTNAME must be set}"

echo "Building darwin configuration..."
nix build ".#darwinConfigurations.${DARWIN_HOSTNAME}.system"
echo "Build successful! Run 'nix run .#switch' to apply."
