#!/usr/bin/env bats
# Home Manager host app scripts choose the same target names as flake.nix.

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  BUILD_SCRIPT="$REPO_ROOT/nix/apps/home-manager-build.sh"
  SWITCH_SCRIPT="$REPO_ROOT/nix/apps/home-manager-switch.sh"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/stub"
  NIX_ARGS_FILE="$WORK/nix.args"
  HM_ARGS_FILE="$WORK/home-manager.args"
  HM_STUB="$WORK/home-manager"

  mkdir -p "$STUB_DIR"

  cat > "$STUB_DIR/nix" <<'EOS'
#!/bin/sh
: "${NIX_STUB_ARGS_FILE:?}"
printf '%s\n' "$@" > "$NIX_STUB_ARGS_FILE"
EOS
  chmod +x "$STUB_DIR/nix"

  cat > "$HM_STUB" <<'EOS'
#!/bin/sh
: "${HM_STUB_ARGS_FILE:?}"
printf '%s\n' "$@" > "$HM_STUB_ARGS_FILE"
EOS
  chmod +x "$HM_STUB"
}

teardown() {
  rm -rf "$WORK"
}

run_home_manager_build() {
  local wsl_mode=$1
  shift

  if [ "$wsl_mode" = "wsl" ]; then
    run env WSL_DISTRO_NAME=Ubuntu \
      PATH="$STUB_DIR:$PATH" \
      HM_TARGET_WSL=alice@wsl-x86_64 \
      HM_TARGET_LINUX=alice@linux-x86_64 \
      NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
      "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT" "$@"
  else
    run env -u WSL_DISTRO_NAME \
      PATH="$STUB_DIR:$PATH" \
      HM_TARGET_WSL=alice@wsl-x86_64 \
      HM_TARGET_LINUX=alice@linux-x86_64 \
      NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
      "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT" "$@"
  fi
}

@test "home-manager-build targets WSL configuration when WSL is detected" {
  run_home_manager_build wsl

  [ "$status" -eq 0 ]
  [[ "$output" == *"Building Home Manager configuration: alice@wsl-x86_64"* ]]
  expected=$(printf '%s\n' \
    "build" \
    '.#homeConfigurations."alice@wsl-x86_64".activationPackage')
  [ "$(cat "$NIX_ARGS_FILE")" = "$expected" ]
}

@test "home-manager-build targets Linux configuration outside WSL" {
  run_home_manager_build linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Building Home Manager configuration: alice@linux-x86_64"* ]]
  expected=$(printf '%s\n' \
    "build" \
    '.#homeConfigurations."alice@linux-x86_64".activationPackage')
  [ "$(cat "$NIX_ARGS_FILE")" = "$expected" ]
}

@test "home-manager-switch delegates to configured home-manager binary" {
  run env WSL_DISTRO_NAME=Ubuntu \
    PATH="$STUB_DIR:$PATH" \
    HM_TARGET_WSL=alice@wsl-aarch64 \
    HM_TARGET_LINUX=alice@linux-aarch64 \
    HM_BIN="$HM_STUB" \
    HM_STUB_ARGS_FILE="$HM_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Switching to Home Manager configuration: alice@wsl-aarch64"* ]]
  expected=$(printf '%s\n' \
    "switch" \
    "-b" \
    "hm-backup" \
    "--flake" \
    ".#alice@wsl-aarch64")
  [ "$(cat "$HM_ARGS_FILE")" = "$expected" ]
}

@test "home-manager-build fails before invoking nix when HM_TARGET_WSL is missing" {
  run env -u HM_TARGET_WSL -u WSL_DISTRO_NAME \
    PATH="$STUB_DIR:$PATH" \
    HM_TARGET_LINUX=alice@linux-x86_64 \
    NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"HM_TARGET_WSL"* ]]
  [ ! -e "$NIX_ARGS_FILE" ]
}
