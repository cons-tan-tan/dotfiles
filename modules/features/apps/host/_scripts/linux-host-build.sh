#!/usr/bin/env bash
set -euo pipefail

nixos_marker=${NIXOS_MARKER_PATH:-/etc/NIXOS}

if [[ -n ${WSL_DISTRO_NAME:-} && -e $nixos_marker ]]; then
  : "${NIXOS_TARGET:?NIXOS_TARGET must be set}"

  echo "Building NixOS-WSL configuration: $NIXOS_TARGET"
  nix build ".#nixosConfigurations.\"$NIXOS_TARGET\".config.system.build.toplevel"
else
  : "${HM_TARGET_WSL:?HM_TARGET_WSL must be set}"
  : "${HM_TARGET_LINUX:?HM_TARGET_LINUX must be set}"

  if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
    target="$HM_TARGET_WSL"
  else
    target="$HM_TARGET_LINUX"
  fi

  echo "Building Home Manager configuration: $target"
  nix build ".#homeConfigurations.\"$target\".activationPackage"
fi

echo "Build successful! Run 'nix run .#switch' to apply."
