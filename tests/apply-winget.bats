#!/usr/bin/env bats
# apply-winget 本体の WSL / WinGet 検出分岐を fixture で検証する。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  SCRIPT="$REPO_ROOT/nix/apps/apply-winget.sh"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  WINDOWS_HOME="$WORK/mnt/d/Users/O'Brien home"
  STUB_DIR="$WORK/stub"
  EMPTY_PATH="$WORK/empty-path"
  WINGET_ARGS_FILE="$WORK/winget.args"
  WSLPATH_ARGS_FILE="$WORK/wslpath.args"
  WINDOWS_CONFIG_PATH="D:\\Users\\O'Brien home\\.config\\dev.winget"

  mkdir -p "$WINDOWS_HOME" "$STUB_DIR" "$EMPTY_PATH"
}

teardown() {
  rm -rf "$WORK"
}

create_windows_config() {
  mkdir -p "$WINDOWS_HOME/.config"
  : > "$WINDOWS_HOME/.config/dev.winget"
}

create_winget_stub() {
  cat > "$STUB_DIR/winget.exe" <<'EOS'
#!/bin/sh
: "${APPLY_WINGET_ARGS_FILE:?}"
printf '%s\n' "$@" > "$APPLY_WINGET_ARGS_FILE"
EOS
  chmod +x "$STUB_DIR/winget.exe"
}

create_wslpath_stub() {
  cat > "$STUB_DIR/wslpath" <<'EOS'
#!/bin/sh
: "${APPLY_WINGET_WSLPATH_ARGS_FILE:?}"
printf '%s\n' "$#" "$@" > "$APPLY_WINGET_WSLPATH_ARGS_FILE"
if [ "${APPLY_WINGET_WSLPATH_STATUS:-0}" -ne 0 ]; then
  exit "$APPLY_WINGET_WSLPATH_STATUS"
fi
printf '%s\n' "${APPLY_WINGET_WSLPATH_OUTPUT:-}"
EOS
  chmod +x "$STUB_DIR/wslpath"
}

run_apply_winget() {
  local wsl_mode=$1
  local path_value=$2
  shift 2

  if [ "$wsl_mode" = "wsl" ]; then
    run env WSL_DISTRO_NAME=Ubuntu \
      PATH="$path_value" \
      APPLY_WINGET_WINDOWS_HOMEDIR="$WINDOWS_HOME" \
      APPLY_WINGET_ARGS_FILE="$WINGET_ARGS_FILE" \
      APPLY_WINGET_WSLPATH_ARGS_FILE="$WSLPATH_ARGS_FILE" \
      APPLY_WINGET_WSLPATH_OUTPUT="$WINDOWS_CONFIG_PATH" \
      "$BASH_BIN" -eu -o pipefail "$SCRIPT" "$@"
  else
    run env -u WSL_DISTRO_NAME \
      PATH="$path_value" \
      APPLY_WINGET_WINDOWS_HOMEDIR="$WINDOWS_HOME" \
      APPLY_WINGET_ARGS_FILE="$WINGET_ARGS_FILE" \
      APPLY_WINGET_WSLPATH_ARGS_FILE="$WSLPATH_ARGS_FILE" \
      APPLY_WINGET_WSLPATH_OUTPUT="$WINDOWS_CONFIG_PATH" \
      "$BASH_BIN" -eu -o pipefail "$SCRIPT" "$@"
  fi
}

@test "fails outside WSL" {
  run_apply_winget non-wsl "$EMPTY_PATH"

  [ "$status" -eq 1 ]
  [[ "$output" == *"apply-winget: not running under WSL"* ]]
}

@test "fails under WSL when WinGet config has not been generated" {
  run_apply_winget wsl "$EMPTY_PATH"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Run 'nix run .#switch' first"* ]]
}

@test "fails when winget.exe is not in PATH" {
  create_windows_config

  run_apply_winget wsl "$EMPTY_PATH"

  [ "$status" -eq 1 ]
  [[ "$output" == *"apply-winget: winget.exe not found"* ]]
}

@test "execs winget.exe configure when Windows home path contains a space" {
  create_windows_config
  create_winget_stub
  create_wslpath_stub

  run_apply_winget wsl "$STUB_DIR" --verbose "name with space"

  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' \
    "configure" \
    "--accept-configuration-agreements" \
    "-f" \
    "$WINDOWS_CONFIG_PATH" \
    "--verbose" \
    "name with space")
  [ "$(cat "$WINGET_ARGS_FILE")" = "$expected" ]

  expected_wslpath=$(printf '%s\n' \
    "2" \
    "-w" \
    "$WINDOWS_HOME/.config/dev.winget")
  [ "$(cat "$WSLPATH_ARGS_FILE")" = "$expected_wslpath" ]
}

@test "does not invoke winget.exe when wslpath conversion fails" {
  create_windows_config
  create_winget_stub
  create_wslpath_stub

  run env WSL_DISTRO_NAME=Ubuntu \
    PATH="$STUB_DIR" \
    APPLY_WINGET_WINDOWS_HOMEDIR="$WINDOWS_HOME" \
    APPLY_WINGET_ARGS_FILE="$WINGET_ARGS_FILE" \
    APPLY_WINGET_WSLPATH_ARGS_FILE="$WSLPATH_ARGS_FILE" \
    APPLY_WINGET_WSLPATH_STATUS=23 \
    "$BASH_BIN" -eu -o pipefail "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to convert"* ]]
  [ ! -e "$WINGET_ARGS_FILE" ]
}

@test "does not invoke winget.exe when wslpath returns an empty path" {
  create_windows_config
  create_winget_stub
  create_wslpath_stub

  run env WSL_DISTRO_NAME=Ubuntu \
    PATH="$STUB_DIR" \
    APPLY_WINGET_WINDOWS_HOMEDIR="$WINDOWS_HOME" \
    APPLY_WINGET_ARGS_FILE="$WINGET_ARGS_FILE" \
    APPLY_WINGET_WSLPATH_ARGS_FILE="$WSLPATH_ARGS_FILE" \
    APPLY_WINGET_WSLPATH_OUTPUT= \
    "$BASH_BIN" -eu -o pipefail "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"returned an empty Windows path"* ]]
  [ ! -e "$WINGET_ARGS_FILE" ]
}
