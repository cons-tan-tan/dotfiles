#!/usr/bin/env bats
# Nix-built executable and host process boundaries; pure behavior lives in Rust tests.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

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
  TARGET="$WORK/nix.custom.conf"
  SNIPPET="$WORK/snippet.conf"
  printf '%s\n' \
    "extra-trusted-users = constantan" \
    "extra-substituters = https://cache.numtide.com" \
    >"$SNIPPET"
}

teardown() {
  chmod -R u+w "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

file_inode() {
  stat -c %i "$1" 2>/dev/null || stat -f %i "$1"
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
