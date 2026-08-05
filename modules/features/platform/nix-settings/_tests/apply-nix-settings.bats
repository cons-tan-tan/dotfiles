#!/usr/bin/env bats
# Nix-built executable and host process boundaries; pure behavior lives in Rust tests.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_lib/bats/test-helper.bash"

setup_file() {
  bats_require_minimum_version 1.5.0

  if [[ -z ${APPLY_NIX_SETTINGS_TEST_BIN:-} ]]; then
    return 0
  fi
  case "$APPLY_NIX_SETTINGS_TEST_BIN" in
  /*) ;;
  *)
    echo "APPLY_NIX_SETTINGS_TEST_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  if [[ ! -x $APPLY_NIX_SETTINGS_TEST_BIN ]]; then
    echo "APPLY_NIX_SETTINGS_TEST_BIN is not executable: $APPLY_NIX_SETTINGS_TEST_BIN" >&2
    return 1
  fi
}

setup() {
  require_nix_fixture APPLY_NIX_SETTINGS_TEST_BIN "unwrapped apply-nix-settings binary"

  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/stub"
  TARGET="$WORK/nix.custom.conf"
  SNIPPET="$WORK/snippet.conf"
  mkdir -p "$STUB_DIR"
  printf '%s\n' \
    "extra-trusted-users = constantan" \
    "extra-substituters = https://cache.numtide.com" \
    >"$SNIPPET"
}

teardown() {
  chmod -R u+w "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

run_apply() {
  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" "$@"
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

file_inode() {
  stat -c %i "$1" 2>/dev/null || stat -f %i "$1"
}

create_sudo_stub() {
  local status=$1
  cat >"$STUB_DIR/sudo" <<EOF
#!$BASH_BIN
printf '%s\\n' "\$@" >"\$SUDO_STUB_LOG"
exit $status
EOF
  chmod +x "$STUB_DIR/sudo"
}

@test "Nix-built core publishes one managed block and is idempotent" {
  printf 'before = keep\n' >"$TARGET"

  run_apply

  [ "$status" -eq 0 ]
  [[ "$output" == *"wrote $TARGET"* ]]
  [ "$(grep -c '^# BEGIN cons-tan-tan/dotfiles apply-nix-settings$' "$TARGET")" -eq 1 ]
  [ "$(grep -c '^# END cons-tan-tan/dotfiles apply-nix-settings$' "$TARGET")" -eq 1 ]
  [[ "$(cat "$TARGET")" == *"before = keep"* ]]
  [[ "$(cat "$TARGET")" == *"extra-trusted-users = constantan"* ]]
  local first_content
  first_content="$(cat "$TARGET")"

  run_apply

  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
  [ "$(cat "$TARGET")" = "$first_content" ]
}

@test "--check exits 1 without writing, locking, or invoking sudo" {
  local missing_parent="$WORK/check-missing"
  local sudo_log="$WORK/check-sudo-called"
  TARGET="$missing_parent/nix.custom.conf"
  create_sudo_stub 88

  run env \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" --check

  [ "$status" -eq 1 ]
  [[ "$output" == *"not up to date"* ]]
  [[ "$output" == *"+extra-trusted-users = constantan"* ]]
  [ ! -e "$missing_parent" ]
  [ ! -e "$sudo_log" ]
}

@test "--dry-run exits 0 without writing, locking, or invoking sudo" {
  local missing_parent="$WORK/dry-run-missing"
  local sudo_log="$WORK/dry-run-sudo-called"
  TARGET="$missing_parent/nix.custom.conf"
  create_sudo_stub 88

  run env \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"+extra-trusted-users = constantan"* ]]
  [[ "$output" != *"not up to date"* ]]
  [ ! -e "$missing_parent" ]
  [ ! -e "$sudo_log" ]
}

@test "sudo exec preserves assignments, current executable, and child status" {
  local locked_dir="$WORK/locked"
  local nix_conf="$WORK/nix.conf"
  local sudo_log="$WORK/sudo.args"
  mkdir "$locked_dir"
  TARGET="$locked_dir/nix.custom.conf"
  printf '!include %s\n' "$TARGET" >"$nix_conf"
  : >"$sudo_log"
  chmod 666 "$sudo_log"
  create_sudo_stub 73
  chmod 555 "$locked_dir"

  run env \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_NIX_CONF="$nix_conf" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN"

  [ "$status" -eq 73 ]
  expected=$(printf '%s\n' \
    "APPLY_NIX_SETTINGS_ELEVATED=1" \
    "APPLY_NIX_SETTINGS_CONF=$TARGET" \
    "APPLY_NIX_SETTINGS_NIX_CONF=$nix_conf" \
    "APPLY_NIX_SETTINGS_SNIPPET=$SNIPPET" \
    "APPLY_NIX_SETTINGS_SUDO=$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN")
  [ "$(cat "$sudo_log")" = "$expected" ]
}

@test "sudo handoff creates no pre-elevation target, lock, or temporary file" {
  local locked_dir="$WORK/pre-elevation"
  local temp_dir="$WORK/tmp"
  local sudo_log="$WORK/sudo.args"
  mkdir "$locked_dir" "$temp_dir"
  TARGET="$locked_dir/nix.custom.conf"
  : >"$sudo_log"
  chmod 666 "$sudo_log"
  create_sudo_stub 0
  chmod 555 "$locked_dir"

  run env \
    TMPDIR="$temp_dir" \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN"

  [ "$status" -eq 0 ]
  [ ! -e "$TARGET" ]
  [ ! -e "$locked_dir/.apply-nix-settings.lock" ]
  [ -z "$(find "$locked_dir" -name '.apply-nix-settings.tmp.*' -print -quit)" ]
  [ -z "$(find "$temp_dir" -mindepth 1 -print -quit)" ]
}

@test "publish is atomic and fixes permissions independently of umask" {
  printf 'before = old\n' >"$TARGET"
  chmod 600 "$TARGET"
  local original_inode
  original_inode="$(file_inode "$TARGET")"

  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    "$BASH_BIN" -c 'umask 077; exec "$1"' _ "$APPLY_NIX_SETTINGS_TEST_BIN"

  [ "$status" -eq 0 ]
  [ "$(file_mode "$TARGET")" = "644" ]
  [ "$(file_inode "$TARGET")" != "$original_inode" ]
  [ -z "$(find "$WORK" -name '.apply-nix-settings.tmp.*' -print -quit)" ]

  local nested_dir="$WORK/new/nix"
  TARGET="$nested_dir/nix.custom.conf"
  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    "$BASH_BIN" -c 'umask 077; exec "$1"' _ "$APPLY_NIX_SETTINGS_TEST_BIN"

  [ "$status" -eq 0 ]
  [ "$(file_mode "$nested_dir")" = "755" ]
  [ "$(file_mode "$TARGET")" = "644" ]
}

@test "public app pins the generated snippet and Rust core" {
  if [[ -z ${APPLY_NIX_SETTINGS_PUBLIC_BIN:-} ]]; then
    skip "APPLY_NIX_SETTINGS_PUBLIC_BIN is only available in the Nix check"
  fi

  local public_script
  public_script="$(readlink -f "$APPLY_NIX_SETTINGS_PUBLIC_BIN")"
  grep -E '^export APPLY_NIX_SETTINGS_SNIPPET=/nix/store/.+-dotfiles-nix-custom.conf$' \
    "$public_script"
  grep -E '^exec /nix/store/.+-apply-nix-settings-0.1.0/bin/apply-nix-settings "\$@"$' \
    "$public_script"

  run "$APPLY_NIX_SETTINGS_PUBLIC_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply-nix-settings"* ]]

  local public_target="$WORK/public/nix.custom.conf"
  run env APPLY_NIX_SETTINGS_CONF="$public_target" \
    "$APPLY_NIX_SETTINGS_PUBLIC_BIN" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"+extra-trusted-users = constantan"* ]]
  [[ "$output" == *"+extra-substituters = https://cache.numtide.com https://nix-community.cachix.org"* ]]
  [ ! -e "$WORK/public" ]
}
