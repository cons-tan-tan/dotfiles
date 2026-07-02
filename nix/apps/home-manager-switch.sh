#!/usr/bin/env bash
set -euo pipefail

: "${HM_USERNAME:?HM_USERNAME must be set}"
: "${HM_ARCH:?HM_ARCH must be set}"
: "${HM_BIN:?HM_BIN must be set}"

if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  target="${HM_USERNAME}@wsl-${HM_ARCH}"
else
  target="${HM_USERNAME}@linux-${HM_ARCH}"
fi

echo "Switching to Home Manager configuration: $target"
# -b: 非管理ファイルと衝突したらバックアップを残して置換する
# (darwin 側の home-manager.backupFileExtension と同じ方針)
"$HM_BIN" switch -b hm-backup --flake ".#$target"
