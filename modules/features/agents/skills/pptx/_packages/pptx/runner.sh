# shellcheck shell=bash

if [ "$#" -eq 0 ]; then
  echo "usage: nix run dotfiles#pptx -- <command> [args...]" >&2
  exit 64
fi

export PATH="$PPTX_RUN_TOOL_PATH/bin:$PATH"
exec "$@"
