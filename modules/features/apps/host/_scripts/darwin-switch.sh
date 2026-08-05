#!/usr/bin/env bash
set -euo pipefail

: "${DARWIN_HOSTNAME:?DARWIN_HOSTNAME must be set}"
: "${DARWIN_REBUILD_BIN:?DARWIN_REBUILD_BIN must be set}"

echo "Building and switching to darwin configuration..."
exec sudo "$DARWIN_REBUILD_BIN" switch --flake ".#${DARWIN_HOSTNAME}"
