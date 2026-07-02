#!/usr/bin/env bash
set -euo pipefail

: "${HM_USERNAME:?HM_USERNAME must be set}"
: "${HM_ARCH:?HM_ARCH must be set}"

if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  target="${HM_USERNAME}@wsl-${HM_ARCH}"
else
  target="${HM_USERNAME}@linux-${HM_ARCH}"
fi

echo "Building Home Manager configuration: $target"
nix build ".#homeConfigurations.\"$target\".activationPackage"
echo "Build successful! Run 'nix run .#switch' to apply."
