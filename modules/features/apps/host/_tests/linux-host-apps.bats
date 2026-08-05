#!/usr/bin/env bats
# Linux host apps keep Ubuntu WSL/Home Manager compatibility while adding NixOS-WSL.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  BUILD_SCRIPT="$REPO_ROOT/modules/features/apps/host/_scripts/linux-host-build.sh"
  SWITCH_SCRIPT="$REPO_ROOT/modules/features/apps/host/_scripts/linux-host-switch.sh"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/stub"
  NIXOS_MARKER="$WORK/NIXOS"
  NIX_ARGS_FILE="$WORK/nix.args"
  HM_ARGS_FILE="$WORK/home-manager.args"
  NIXOS_REBUILD_ARGS_FILE="$WORK/nixos-rebuild.args"
  WSL_INSTALLER_ARGS_FILE="$WORK/wsl-installer.args"
  SUDO_ARGS_FILE="$WORK/sudo.args"
  HM_STUB="$WORK/home-manager"
  NIXOS_REBUILD_STUB="$WORK/nixos-rebuild"
  WSL_INSTALLER_STUB="$WORK/install-nh-cleanup-systemd"

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
"$@"
EOS
  chmod +x "$STUB_DIR/sudo"

  cat > "$HM_STUB" <<'EOS'
#!/bin/sh
: "${HM_STUB_ARGS_FILE:?}"
printf '%s\n' "$@" > "$HM_STUB_ARGS_FILE"
EOS
  chmod +x "$HM_STUB"

  cat > "$NIXOS_REBUILD_STUB" <<'EOS'
#!/bin/sh
: "${NIXOS_REBUILD_STUB_ARGS_FILE:?}"
printf '%s\n' "$@" > "$NIXOS_REBUILD_STUB_ARGS_FILE"
EOS
  chmod +x "$NIXOS_REBUILD_STUB"

  cat > "$WSL_INSTALLER_STUB" <<'EOS'
#!/bin/sh
: "${WSL_INSTALLER_STUB_ARGS_FILE:?}"
printf '%s\n' "$@" > "$WSL_INSTALLER_STUB_ARGS_FILE"
exit "${WSL_INSTALLER_STUB_STATUS:-0}"
EOS
  chmod +x "$WSL_INSTALLER_STUB"
}

teardown() {
  rm -rf "$WORK"
}

run_linux_host_build() {
  local mode=$1

  case "$mode" in
    nixos-wsl)
      touch "$NIXOS_MARKER"
      run env WSL_DISTRO_NAME=NixOS \
        NIXOS_MARKER_PATH="$NIXOS_MARKER" \
        NIXOS_TARGET=wsl \
        PATH="$STUB_DIR:$PATH" \
        NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
        "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"
      ;;
    ubuntu-wsl)
      run env WSL_DISTRO_NAME=Ubuntu \
        NIXOS_MARKER_PATH="$NIXOS_MARKER" \
        HM_TARGET_WSL=alice@wsl-x86_64 \
        HM_TARGET_LINUX=alice@linux-x86_64 \
        PATH="$STUB_DIR:$PATH" \
        NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
        "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"
      ;;
    linux)
      run env -u WSL_DISTRO_NAME \
        NIXOS_MARKER_PATH="$NIXOS_MARKER" \
        HM_TARGET_WSL=alice@wsl-x86_64 \
        HM_TARGET_LINUX=alice@linux-x86_64 \
        PATH="$STUB_DIR:$PATH" \
        NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
        "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"
      ;;
  esac
}

@test "linux-host-build targets NixOS configuration on NixOS-WSL" {
  run_linux_host_build nixos-wsl

  [ "$status" -eq 0 ]
  [[ "$output" == *"Building NixOS-WSL configuration: wsl"* ]]
  expected=$(printf '%s\n' \
    "build" \
    '.#nixosConfigurations."wsl".config.system.build.toplevel')
  [ "$(cat "$NIX_ARGS_FILE")" = "$expected" ]
}

@test "linux-host-build keeps standalone Home Manager on Ubuntu WSL" {
  run_linux_host_build ubuntu-wsl

  [ "$status" -eq 0 ]
  [[ "$output" == *"Building Home Manager configuration: alice@wsl-x86_64"* ]]
  expected=$(printf '%s\n' \
    "build" \
    '.#homeConfigurations."alice@wsl-x86_64".activationPackage')
  [ "$(cat "$NIX_ARGS_FILE")" = "$expected" ]
}

@test "linux-host-build targets Linux Home Manager outside WSL" {
  run_linux_host_build linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Building Home Manager configuration: alice@linux-x86_64"* ]]
  expected=$(printf '%s\n' \
    "build" \
    '.#homeConfigurations."alice@linux-x86_64".activationPackage')
  [ "$(cat "$NIX_ARGS_FILE")" = "$expected" ]
}

@test "NixOS marker alone does not select the NixOS-WSL configuration" {
  touch "$NIXOS_MARKER"

  run_linux_host_build linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Building Home Manager configuration: alice@linux-x86_64"* ]]
}

@test "linux-host-switch runs nixos-rebuild through sudo on NixOS-WSL" {
  touch "$NIXOS_MARKER"

  run env WSL_DISTRO_NAME=NixOS \
    NIXOS_MARKER_PATH="$NIXOS_MARKER" \
    NIXOS_TARGET=wsl \
    NIXOS_REBUILD_BIN="$NIXOS_REBUILD_STUB" \
    NIXOS_REBUILD_STUB_ARGS_FILE="$NIXOS_REBUILD_ARGS_FILE" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
    PATH="$STUB_DIR:$PATH" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Switching to NixOS-WSL configuration: wsl"* ]]
  expected_sudo=$(printf '%s\n' \
    "$NIXOS_REBUILD_STUB" \
    "switch" \
    "--flake" \
    ".#wsl")
  [ "$(cat "$SUDO_ARGS_FILE")" = "$expected_sudo" ]
  expected_rebuild=$(printf '%s\n' \
    "switch" \
    "--flake" \
    ".#wsl")
  [ "$(cat "$NIXOS_REBUILD_ARGS_FILE")" = "$expected_rebuild" ]
}

@test "linux-host-switch keeps standalone Home Manager on Ubuntu WSL" {
  run env WSL_DISTRO_NAME=Ubuntu \
    NIXOS_MARKER_PATH="$NIXOS_MARKER" \
    HM_TARGET_WSL=alice@wsl-aarch64 \
    HM_TARGET_LINUX=alice@linux-aarch64 \
    HM_BIN="$HM_STUB" \
    HM_STUB_ARGS_FILE="$HM_ARGS_FILE" \
    NH_CLEANUP_SYSTEMD_INSTALLER="$WSL_INSTALLER_STUB" \
    WSL_INSTALLER_STUB_ARGS_FILE="$WSL_INSTALLER_ARGS_FILE" \
    SUDO_BIN="$STUB_DIR/sudo" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
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
  [ "$(cat "$SUDO_ARGS_FILE")" = "$WSL_INSTALLER_STUB" ]
  [ -z "$(cat "$WSL_INSTALLER_ARGS_FILE")" ]
}

@test "Ubuntu WSL switch stops before Home Manager when system timer installation fails" {
  run env WSL_DISTRO_NAME=Ubuntu \
    NIXOS_MARKER_PATH="$NIXOS_MARKER" \
    HM_TARGET_WSL=alice@wsl-x86_64 \
    HM_TARGET_LINUX=alice@linux-x86_64 \
    HM_BIN="$HM_STUB" \
    HM_STUB_ARGS_FILE="$HM_ARGS_FILE" \
    NH_CLEANUP_SYSTEMD_INSTALLER="$WSL_INSTALLER_STUB" \
    WSL_INSTALLER_STUB_ARGS_FILE="$WSL_INSTALLER_ARGS_FILE" \
    WSL_INSTALLER_STUB_STATUS=49 \
    SUDO_BIN="$STUB_DIR/sudo" \
    SUDO_STUB_ARGS_FILE="$SUDO_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$SWITCH_SCRIPT"

  [ "$status" -eq 49 ]
  [ ! -e "$HM_ARGS_FILE" ]
}

@test "NixOS-WSL build fails before invoking nix when NIXOS_TARGET is missing" {
  touch "$NIXOS_MARKER"

  run env -u NIXOS_TARGET \
    WSL_DISTRO_NAME=NixOS \
    NIXOS_MARKER_PATH="$NIXOS_MARKER" \
    PATH="$STUB_DIR:$PATH" \
    NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"NIXOS_TARGET"* ]]
  [ ! -e "$NIX_ARGS_FILE" ]
}

@test "Home Manager build fails before invoking nix when HM target is missing" {
  run env -u HM_TARGET_WSL \
    WSL_DISTRO_NAME=Ubuntu \
    NIXOS_MARKER_PATH="$NIXOS_MARKER" \
    HM_TARGET_LINUX=alice@linux-x86_64 \
    PATH="$STUB_DIR:$PATH" \
    NIX_STUB_ARGS_FILE="$NIX_ARGS_FILE" \
    "$BASH_BIN" -eu -o pipefail "$BUILD_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"HM_TARGET_WSL"* ]]
  [ ! -e "$NIX_ARGS_FILE" ]
}

@test "Nix public host apps pin Home Manager and architecture-matched NixOS targets" {
  if [[ ${HOST_APP_KIND:-} != linux-host ]]; then
    skip "Linux host public apps are only available in Linux Nix checks"
  fi

  local build_script switch_script
  build_script="$(readlink -f "$HOST_BUILD_PUBLIC_BIN")"
  switch_script="$(readlink -f "$HOST_SWITCH_PUBLIC_BIN")"

  grep -Fqx "export HM_TARGET_WSL=$HOST_EXPECTED_HM_WSL" "$build_script"
  grep -Fqx "export HM_TARGET_LINUX=$HOST_EXPECTED_HM_LINUX" "$build_script"
  grep -Fqx "export NIXOS_TARGET=$HOST_EXPECTED_NIXOS_WSL" "$build_script"
  grep -Fqx "export HM_TARGET_WSL=$HOST_EXPECTED_HM_WSL" "$switch_script"
  grep -Fqx "export HM_TARGET_LINUX=$HOST_EXPECTED_HM_LINUX" "$switch_script"
  grep -E '^export HM_BIN=/nix/store/.+-home-manager/bin/home-manager$' "$switch_script"
  grep -Fqx "export NIXOS_TARGET=$HOST_EXPECTED_NIXOS_WSL" "$switch_script"
  grep -E '^export NIXOS_REBUILD_BIN=/nix/store/.+/bin/nixos-rebuild$' "$switch_script"
  grep -F 'nix build ".#nixosConfigurations.\"$NIXOS_TARGET\".config.system.build.toplevel"' \
    "$build_script"
  grep -F 'nix build ".#homeConfigurations.\"$target\".activationPackage"' "$build_script"
  grep -F '"$sudo_bin" "$NIXOS_REBUILD_BIN" switch --flake ".#$NIXOS_TARGET"' \
    "$switch_script"
  grep -F '"$HM_BIN" switch -b hm-backup --flake ".#$target"' "$switch_script"
  grep -E '^export NH_CLEANUP_SYSTEMD_INSTALLER=/nix/store/.+/bin/install-nh-cleanup-systemd$' "$switch_script"
}
