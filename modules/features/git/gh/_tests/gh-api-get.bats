#!/usr/bin/env bats
# Nix package/process boundaries only; the complete option policy lives in Rust tests.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup_file() {
  bats_require_minimum_version 1.5.0

  if [[ -z ${GH_API_GET_PUBLIC_BIN:-} ]]; then
    return 0
  fi
  case "$GH_API_GET_PUBLIC_BIN" in
  /*) ;;
  *)
    echo "GH_API_GET_PUBLIC_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  if [[ ! -x $GH_API_GET_PUBLIC_BIN ]]; then
    echo "GH_API_GET_PUBLIC_BIN is not executable: $GH_API_GET_PUBLIC_BIN" >&2
    return 1
  fi
}

setup() {
  require_nix_fixture GH_API_GET_PUBLIC_BIN "public gh-api-get binary"
}

@test "extension root keeps the gh extension executable contract" {
  if [[ -z ${GH_API_GET_EXTENSION_ROOT:-} ]]; then
    skip "GH_API_GET_EXTENSION_ROOT is only available in the Nix check"
  fi

  [ -L "$GH_API_GET_EXTENSION_ROOT/gh-api-get" ]
  [ -x "$GH_API_GET_EXTENSION_ROOT/gh-api-get" ]

  run "$GH_API_GET_EXTENSION_ROOT/gh-api-get" --help
  [ "$status" -eq 0 ]
}

@test "public wrapper pins the gh child" {
  if [[ -z ${GH_API_GET_PUBLIC_BIN:-} ]]; then
    skip "GH_API_GET_PUBLIC_BIN is only available in the Nix check"
  fi

  local public_script
  public_script="$(readlink -f "$GH_API_GET_PUBLIC_BIN")"
  grep -E "^export SAFE_FETCH_GH_BIN='/nix/store/.+-gh-.+/bin/gh'$" "$public_script"

  run "$GH_API_GET_PUBLIC_BIN" --help
  [ "$status" -eq 0 ]
}
