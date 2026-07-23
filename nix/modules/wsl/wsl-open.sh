: "${WSL_OPEN_REALPATH_BIN:?WSL_OPEN_REALPATH_BIN must be set}"
: "${WSL_OPEN_WSLPATH_BIN:?WSL_OPEN_WSLPATH_BIN must be set}"
: "${WSL_OPEN_HANDLER_BIN:?WSL_OPEN_HANDLER_BIN must be set}"

if [[ -z ${WSL_DISTRO_NAME:-} ]]; then
  echo "wsl-open: not running under WSL" >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: wsl-open URL_OR_PATH" >&2
  exit 1
fi

target=$1
case "$target" in
*://* | mailto:*) ;;
*)
  target=$("$WSL_OPEN_REALPATH_BIN" -- "$target")
  target=$("$WSL_OPEN_WSLPATH_BIN" -w "$target")
  ;;
esac

exec "$WSL_OPEN_HANDLER_BIN" url.dll,FileProtocolHandler "$target"
