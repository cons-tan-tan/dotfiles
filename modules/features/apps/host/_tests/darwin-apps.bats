#!/usr/bin/env bats
# Darwin app scripts choose the same target names as flake.nix.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  BUILD_SCRIPT="$REPO_ROOT/modules/features/apps/host/_scripts/darwin-build.sh"
  SWITCH_SCRIPT="$REPO_ROOT/modules/features/apps/host/_scripts/darwin-switch.sh"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/stub"
  NIX_ARGS_FILE="$WORK/nix.args"
  SUDO_ARGS_FILE="$WORK/sudo.args"
  DARWIN_REBUILD_BIN="$WORK/nix store/bin/darwin-rebuild"

  mkdir -p "$STUB_DIR" "$(dirname "$DARWIN_REBUILD_BIN")"

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

  cat > "$DARWIN_REBUILD_BIN" <<'EOS'
#!/bin/sh
exit 99
EOS
  chmod +x "$DARWIN_REBUILD_BIN"
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

@test "darwin-switch delegates to sudo with the pinned darwin-rebuild executable" {
  run env DARWIN_HOSTNAME=testhost \
    DARWIN_REBUILD_BIN="$DARWIN_REBUILD_BIN" \
    PATH="$STUB_DIR:$PATH" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' \
    "$DARWIN_REBUILD_BIN" \
    "switch" \
    "--flake" \
    ".#testhost")
  [ "$(cat "$SUDO_ARGS_FILE")" = "$expected" ]
  [ ! -e "$NIX_ARGS_FILE" ]
}

@test "darwin-switch fails before invoking sudo when DARWIN_HOSTNAME is missing" {
  run env -u DARWIN_HOSTNAME \
    DARWIN_REBUILD_BIN="$DARWIN_REBUILD_BIN" \
    PATH="$STUB_DIR:$PATH" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"DARWIN_HOSTNAME"* ]]
  [ ! -e "$SUDO_ARGS_FILE" ]
}

@test "darwin-switch fails before invoking sudo when DARWIN_REBUILD_BIN is missing" {
  run env -u DARWIN_REBUILD_BIN \
    DARWIN_HOSTNAME=testhost \
    PATH="$STUB_DIR:$PATH" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"DARWIN_REBUILD_BIN"* ]]
  [ ! -e "$SUDO_ARGS_FILE" ]
}

@test "Nix public host apps pin the Darwin hostname and rebuild executable" {
  if [[ ${HOST_APP_KIND:-} != darwin ]]; then
    skip "Darwin public apps are only available in Darwin Nix checks"
  fi

  local build_script switch_script
  build_script="$(readlink -f "$HOST_BUILD_PUBLIC_BIN")"
  switch_script="$(readlink -f "$HOST_SWITCH_PUBLIC_BIN")"

  grep -Fx "export DARWIN_HOSTNAME=constantan" "$build_script"
  grep -Fx "export DARWIN_HOSTNAME=constantan" "$switch_script"
  grep -F 'nix build ".#darwinConfigurations.${DARWIN_HOSTNAME}.system"' "$build_script"
  grep -F 'exec sudo "$DARWIN_REBUILD_BIN" switch --flake ".#${DARWIN_HOSTNAME}"' \
    "$switch_script"
  grep -E '^export DARWIN_REBUILD_BIN=/nix/store/.+-darwin-rebuild/bin/darwin-rebuild$' \
    "$switch_script"
}
