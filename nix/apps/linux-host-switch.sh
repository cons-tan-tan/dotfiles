#!/usr/bin/env bash
set -euo pipefail

nixos_marker=${NIXOS_MARKER_PATH:-/etc/NIXOS}

if [[ -n ${WSL_DISTRO_NAME:-} && -e $nixos_marker ]]; then
  : "${NIXOS_TARGET:?NIXOS_TARGET must be set}"
  : "${NIXOS_REBUILD_BIN:?NIXOS_REBUILD_BIN must be set}"

  sudo_bin=${SUDO_BIN:-sudo}
  echo "Switching to NixOS-WSL configuration: $NIXOS_TARGET"
  "$sudo_bin" "$NIXOS_REBUILD_BIN" switch --flake ".#$NIXOS_TARGET"
else
  : "${HM_TARGET_WSL:?HM_TARGET_WSL must be set}"
  : "${HM_TARGET_LINUX:?HM_TARGET_LINUX must be set}"
  : "${HM_BIN:?HM_BIN must be set}"

  if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
    target="$HM_TARGET_WSL"
  else
    target="$HM_TARGET_LINUX"
  fi

  echo "Switching to Home Manager configuration: $target"
  # 非管理ファイルと衝突した場合はバックアップを残して置換する。
  "$HM_BIN" switch -b hm-backup --flake ".#$target"
fi
