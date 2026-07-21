#!/usr/bin/env bash
set -euo pipefail

: "${HM_TARGET_WSL:?HM_TARGET_WSL must be set}"
: "${HM_TARGET_LINUX:?HM_TARGET_LINUX must be set}"
: "${HM_BIN:?HM_BIN must be set}"

if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  target="$HM_TARGET_WSL"
else
  target="$HM_TARGET_LINUX"
fi

echo "Switching to Home Manager configuration: $target"
# -b: 非管理ファイルと衝突したらバックアップを残して置換する
# (darwin 側の home-manager.backupFileExtension と同じ方針)
"$HM_BIN" switch -b hm-backup --flake ".#$target"
