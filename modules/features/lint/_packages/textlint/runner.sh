# shellcheck shell=bash

usage() {
  cat >&2 <<'EOF'
usage: nix run dotfiles#textlint -- tech-jp <files...>

modes:
  tech-jp  Lint Japanese technical documentation with textlint.
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 64
fi

mode="$1"
shift

case "$mode" in
tech-jp)
  config="$TEXTLINT_RUN_TECH_JP_CONFIG"
  ;;
-h | --help | help)
  usage
  exit 0
  ;;
*)
  echo "textlint: unknown mode: $mode" >&2
  usage
  exit 64
  ;;
esac

if [ "$#" -eq 0 ]; then
  usage
  exit 64
fi

exec "$TEXTLINT_RUN_LINT" \
  --config "$config" \
  "$@"
