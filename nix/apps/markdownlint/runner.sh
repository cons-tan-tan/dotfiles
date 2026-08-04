# shellcheck shell=bash

usage() {
  cat >&2 <<'EOF'
usage: nix run dotfiles#markdownlint -- <files...>
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 64
fi

case "$1" in
-h | --help | help)
  usage
  exit 0
  ;;
esac

exec "$MARKDOWNLINT_RUN_LINT" \
  --config "$MARKDOWNLINT_RUN_CONFIG" \
  "$@"
