#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/test-helper.bash"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/drawio-headless/drawio-wrapper.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  write_bash_stub "$TEST_TMPDIR/dbus-run-session" <<'SH'
printf '%s\n' "$XDG_CONFIG_HOME" >"$TEST_TMPDIR/xdg-config-home"
printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/args"
if [ "${DRAWIO_STUB_STDERR:-}" = "1" ]; then
  printf 'dbus-daemon[123]: Activating service\n' >&2
  printf 'drawio: renderer warning\n' >&2
fi
exit "${DRAWIO_STUB_STATUS:-0}"
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_wrapper() {
  run env \
    DRAWIO_DBUS_SESSION_CONF=/nix/store/dbus/share/dbus-1/session.conf \
    DRAWIO_DBUS_RUN_SESSION_BIN="$TEST_TMPDIR/dbus-run-session" \
    DRAWIO_XVFB_RUN_BIN=xvfb-run-stub \
    DRAWIO_BIN=drawio-stub \
    "$@" \
    bash -euo pipefail "$SCRIPT" "input file.drawio" --export
}

@test "forwards the headless command and keeps Electron flags around user arguments" {
  run_wrapper

  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' \
    "arg:--config-file=/nix/store/dbus/share/dbus-1/session.conf" \
    "arg:--" \
    "arg:xvfb-run-stub" \
    "arg:--auto-display" \
    "arg:--server-args=-screen 0 1024x768x24 -nolisten unix -nolisten tcp" \
    "arg:drawio-stub" \
    "arg:--no-sandbox" \
    "arg:input file.drawio" \
    "arg:--export" \
    "arg:--disable-gpu")
  [ "$(cat "$TEST_TMPDIR/args")" = "$expected" ]
}

@test "uses an isolated XDG config directory and removes it on exit" {
  run_wrapper

  [ "$status" -eq 0 ]
  xdg_config_home=$(cat "$TEST_TMPDIR/xdg-config-home")
  [ -n "$xdg_config_home" ]
  [ ! -e "$xdg_config_home" ]
}

@test "preserves the wrapped command exit status and still cleans up" {
  run_wrapper DRAWIO_STUB_STATUS=7

  [ "$status" -eq 7 ]
  xdg_config_home=$(cat "$TEST_TMPDIR/xdg-config-home")
  [ ! -e "$xdg_config_home" ]
}

@test "filters dbus daemon noise without hiding other stderr" {
  run_wrapper DRAWIO_STUB_STDERR=1

  [ "$status" -eq 0 ]
  [[ "$output" != *"dbus-daemon[123]"* ]]
  [[ "$output" == *"drawio: renderer warning"* ]]
}
