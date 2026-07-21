#!/usr/bin/env bash
set -euo pipefail

: "${HM_TARGET_WSL:?HM_TARGET_WSL must be set}"
: "${HM_TARGET_LINUX:?HM_TARGET_LINUX must be set}"

if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  target="$HM_TARGET_WSL"
else
  target="$HM_TARGET_LINUX"
fi

echo "Building Home Manager configuration: $target"
nix build ".#homeConfigurations.\"$target\".activationPackage"
echo "Build successful! Run 'nix run .#switch' to apply."
