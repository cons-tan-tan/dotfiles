: "${DRAWIO_DBUS_SESSION_CONF:?DRAWIO_DBUS_SESSION_CONF must be set}"

dbus_run_session=${DRAWIO_DBUS_RUN_SESSION_BIN:-dbus-run-session}
xvfb_run=${DRAWIO_XVFB_RUN_BIN:-xvfb-run}
drawio_bin=${DRAWIO_BIN:-drawio}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

XDG_CONFIG_HOME="$tmpdir" \
  "$dbus_run_session" --config-file="$DRAWIO_DBUS_SESSION_CONF" -- \
  "$xvfb_run" \
  --auto-display \
  --server-args="-screen 0 1024x768x24 -nolisten unix -nolisten tcp" \
  "$drawio_bin" --no-sandbox "$@" --disable-gpu \
  2> >(grep --line-buffered -E -v '^dbus-daemon\[[0-9]+\]:' >&2 || true)
