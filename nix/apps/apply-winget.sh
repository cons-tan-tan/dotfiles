#!/usr/bin/env bash
set -euo pipefail

: "${APPLY_WINGET_WINDOWS_HOMEDIR:?APPLY_WINGET_WINDOWS_HOMEDIR must be set}"
: "${APPLY_WINGET_WINDOWS_USERNAME:?APPLY_WINGET_WINDOWS_USERNAME must be set}"

if [[ -z ${WSL_DISTRO_NAME:-} ]]; then
  echo "apply-winget: not running under WSL" >&2
  exit 1
fi

WIN_CONFIG="${APPLY_WINGET_WINDOWS_HOMEDIR}/.config/dev.winget"
if [ ! -f "$WIN_CONFIG" ]; then
  echo "apply-winget: $WIN_CONFIG not found. Run 'nix run .#switch' first." >&2
  exit 1
fi

WINGET_BIN=$(command -v winget.exe || true)
if [ -z "$WINGET_BIN" ]; then
  echo "apply-winget: winget.exe not found in PATH. Ensure WSL interop is enabled." >&2
  exit 1
fi

WIN_CONFIG_PATH="C:\\Users\\${APPLY_WINGET_WINDOWS_USERNAME}\\.config\\dev.winget"
exec "$WINGET_BIN" configure \
  --accept-configuration-agreements \
  -f "$WIN_CONFIG_PATH" "$@"
