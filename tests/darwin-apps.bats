#!/usr/bin/env bats
# Darwin app scripts choose the same target names as flake.nix.

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  BUILD_SCRIPT="$REPO_ROOT/nix/apps/darwin-build.sh"
  SWITCH_SCRIPT="$REPO_ROOT/nix/apps/darwin-switch.sh"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/stub"
  NIX_ARGS_FILE="$WORK/nix.args"
  SUDO_ARGS_FILE="$WORK/sudo.args"

  mkdir -p "$STUB_DIR"

  cat > "$STUB_DIR/nix" <<'EOS'
#!/bin/sh
: "${NIX_STUB_ARGS_FILE:?}"
printf '%s\n' "$@" > "$NIX_STUB_ARGS_FILE"
EOS
  chmod +x "$STUB_DIR/nix"

  cat > "$STUB_DIR/sudo" <<'EOS'
#!/bin/sh
: "${SUDO_STUB_ARGS_FILE:?}"
printf '%s\n' "$@" > "$SUDO_STUB_ARGS_FILE"
EOS
  chmod +x "$STUB_DIR/sudo"
}

teardown() {
  rm -rf "$WORK"
}

@test "darwin-build targets the hostname's system attribute" {
  run env DARWIN_HOSTNAME=testhost \
    PATH="$STUB_DIR:$PATH" \
    NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Building darwin configuration..."* ]]
  expected=$(printf '%s\n' \
    "build" \
    ".#darwinConfigurations.testhost.system")
  [ "$(cat "$NIX_ARGS_FILE")" = "$expected" ]
}

@test "darwin-build fails before invoking nix when DARWIN_HOSTNAME is missing" {
  run env -u DARWIN_HOSTNAME \
    PATH="$STUB_DIR:$PATH" \
    NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"DARWIN_HOSTNAME"* ]]
  [ ! -e "$NIX_ARGS_FILE" ]
}

@test "darwin-switch delegates to sudo nix run nix-darwin" {
  run env DARWIN_HOSTNAME=testhost \
    PATH="$STUB_DIR:$PATH" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' \
    "nix" \
    "run" \
    "nix-darwin" \
    "--" \
    "switch" \
    "--flake" \
    ".#testhost")
  [ "$(cat "$SUDO_ARGS_FILE")" = "$expected" ]
}

@test "darwin-switch fails before invoking sudo when DARWIN_HOSTNAME is missing" {
  run env -u DARWIN_HOSTNAME \
    PATH="$STUB_DIR:$PATH" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"DARWIN_HOSTNAME"* ]]
  [ ! -e "$SUDO_ARGS_FILE" ]
}
