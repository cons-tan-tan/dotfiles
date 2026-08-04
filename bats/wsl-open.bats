#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  SCRIPT="$REPO_ROOT/nix/packages/wsl-open/wsl-open.sh"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/stub"
  REALPATH_ARGS="$WORK/realpath.args"
  WSLPATH_ARGS="$WORK/wslpath.args"
  HANDLER_ARGS="$WORK/handler.args"

  mkdir -p "$STUB_DIR"

  cat >"$STUB_DIR/realpath" <<'EOF'
#!/bin/sh
printf '%s\n' "$#" "$@" >"$WSL_OPEN_REALPATH_ARGS"
if [ "${WSL_OPEN_REALPATH_STATUS:-0}" -ne 0 ]; then
  exit "$WSL_OPEN_REALPATH_STATUS"
fi
printf '%s\n' "${WSL_OPEN_REALPATH_OUTPUT:-/resolved/path}"
EOF

  cat >"$STUB_DIR/wslpath" <<'EOF'
#!/bin/sh
printf '%s\n' "$#" "$@" >"$WSL_OPEN_WSLPATH_ARGS"
if [ "${WSL_OPEN_WSLPATH_STATUS:-0}" -ne 0 ]; then
  exit "$WSL_OPEN_WSLPATH_STATUS"
fi
printf '%s\n' "${WSL_OPEN_WSLPATH_OUTPUT:-C:\\resolved\\path}"
EOF

  cat >"$STUB_DIR/rundll32.exe" <<'EOF'
#!/bin/sh
printf '%s\n' "$#" "$@" >"$WSL_OPEN_HANDLER_ARGS"
exit "${WSL_OPEN_HANDLER_STATUS:-0}"
EOF

  chmod +x "$STUB_DIR/realpath" "$STUB_DIR/wslpath" "$STUB_DIR/rundll32.exe"
}

teardown() {
  rm -rf "$WORK"
}

run_wsl_open() {
  run env \
    WSL_DISTRO_NAME=Ubuntu \
    WSL_OPEN_REALPATH_BIN="$STUB_DIR/realpath" \
    WSL_OPEN_WSLPATH_BIN="$STUB_DIR/wslpath" \
    WSL_OPEN_HANDLER_BIN="$STUB_DIR/rundll32.exe" \
    WSL_OPEN_REALPATH_ARGS="$REALPATH_ARGS" \
    WSL_OPEN_WSLPATH_ARGS="$WSLPATH_ARGS" \
    WSL_OPEN_HANDLER_ARGS="$HANDLER_ARGS" \
    WSL_OPEN_REALPATH_OUTPUT="${REALPATH_OUTPUT:-/resolved/path}" \
    WSL_OPEN_WSLPATH_OUTPUT="${WSLPATH_OUTPUT:-C:\\resolved\\path}" \
    WSL_OPEN_REALPATH_STATUS="${REALPATH_STATUS:-0}" \
    WSL_OPEN_WSLPATH_STATUS="${WSLPATH_STATUS:-0}" \
    WSL_OPEN_HANDLER_STATUS="${HANDLER_STATUS:-0}" \
    "$BASH_BIN" -eu -o pipefail "$SCRIPT" "$@"
}

@test "rejects execution outside WSL" {
  run env -u WSL_DISTRO_NAME \
    WSL_OPEN_REALPATH_BIN="$STUB_DIR/realpath" \
    WSL_OPEN_WSLPATH_BIN="$STUB_DIR/wslpath" \
    WSL_OPEN_HANDLER_BIN="$STUB_DIR/rundll32.exe" \
    "$BASH_BIN" -eu -o pipefail "$SCRIPT" https://example.com

  [ "$status" -eq 1 ]
  [[ "$output" == *"not running under WSL"* ]]
  [ ! -e "$HANDLER_ARGS" ]
}

@test "requires exactly one target" {
  run_wsl_open
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: wsl-open URL_OR_PATH"* ]]

  run_wsl_open first second
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: wsl-open URL_OR_PATH"* ]]
  [ ! -e "$HANDLER_ARGS" ]
}

@test "passes URL and mailto targets through without path conversion" {
  run_wsl_open https://example.com/a
  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' 2 url.dll,FileProtocolHandler https://example.com/a)
  [ "$(cat "$HANDLER_ARGS")" = "$expected" ]
  [ ! -e "$REALPATH_ARGS" ]
  [ ! -e "$WSLPATH_ARGS" ]

  rm -f "$HANDLER_ARGS"
  run_wsl_open mailto:user@example.com
  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' 2 url.dll,FileProtocolHandler mailto:user@example.com)
  [ "$(cat "$HANDLER_ARGS")" = "$expected" ]
  [ ! -e "$REALPATH_ARGS" ]
  [ ! -e "$WSLPATH_ARGS" ]
}

@test "resolves and converts a local path as one argument" {
  local source_path="$WORK/path with spaces"
  local resolved_path="/resolved/path with spaces"
  local windows_path="D:\\resolved\\path with spaces"

  REALPATH_OUTPUT="$resolved_path" \
    WSLPATH_OUTPUT="$windows_path" \
    run_wsl_open "$source_path"

  [ "$status" -eq 0 ]
  expected_realpath=$(printf '%s\n' 2 -- "$source_path")
  [ "$(cat "$REALPATH_ARGS")" = "$expected_realpath" ]
  expected_wslpath=$(printf '%s\n' 2 -w "$resolved_path")
  [ "$(cat "$WSLPATH_ARGS")" = "$expected_wslpath" ]
  expected_handler=$(printf '%s\n' 2 url.dll,FileProtocolHandler "$windows_path")
  [ "$(cat "$HANDLER_ARGS")" = "$expected_handler" ]
}

@test "propagates realpath wslpath and handler failures" {
  REALPATH_STATUS=21 run_wsl_open "$WORK/file"
  [ "$status" -eq 21 ]
  [ ! -e "$WSLPATH_ARGS" ]
  [ ! -e "$HANDLER_ARGS" ]

  WSLPATH_STATUS=22 run_wsl_open "$WORK/file"
  [ "$status" -eq 22 ]
  [ ! -e "$HANDLER_ARGS" ]

  HANDLER_STATUS=23 run_wsl_open https://example.com
  [ "$status" -eq 23 ]
}

@test "Nix package exposes wsl-open and x-www-browser as the same executable" {
  if [[ -z ${WSL_OPEN_TEST_PACKAGE:-} ]]; then
    skip "WSL_OPEN_TEST_PACKAGE is only available in the Nix check"
  fi

  [ "$(readlink -f "$WSL_OPEN_TEST_PACKAGE/bin/wsl-open")" = \
    "$(readlink -f "$WSL_OPEN_TEST_PACKAGE/bin/x-www-browser")" ]

  run env WSL_DISTRO_NAME=Ubuntu TEST_TMPDIR="$WORK" \
    "$WSL_OPEN_TEST_PACKAGE/bin/wsl-open" "$WORK/package path"

  [ "$status" -eq 0 ]
  expected_realpath=$(printf '%s\n' 2 -- "$WORK/package path")
  [ "$(cat "$WORK/package-realpath.args")" = "$expected_realpath" ]
  expected_wslpath=$(printf '%s\n' 2 -w "/package/resolved path")
  [ "$(cat "$WORK/package-wslpath.args")" = "$expected_wslpath" ]
  expected_handler=$(printf '%s\n' 2 url.dll,FileProtocolHandler 'Z:\package\resolved path')
  [ "$(cat "$WORK/package-handler.args")" = "$expected_handler" ]
}
