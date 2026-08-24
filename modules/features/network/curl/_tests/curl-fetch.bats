#!/usr/bin/env bats
# Nix package/process boundaries only; the complete option policy lives in Rust tests.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup_file() {
  bats_require_minimum_version 1.5.0

  if [[ -z ${CURL_FETCH_PUBLIC_BIN:-} ]]; then
    return 0
  fi
  case "$CURL_FETCH_PUBLIC_BIN" in
  /*) ;;
  *)
    echo "CURL_FETCH_PUBLIC_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  if [[ ! -x $CURL_FETCH_PUBLIC_BIN ]]; then
    echo "CURL_FETCH_PUBLIC_BIN is not executable: $CURL_FETCH_PUBLIC_BIN" >&2
    return 1
  fi
}

setup() {
  require_nix_fixture CURL_FETCH_PUBLIC_BIN "public curl-fetch binary"
}

@test "public wrapper fixes the child and clears key logging environments" {
  if [[ -z ${CURL_FETCH_PUBLIC_BIN:-} ]]; then
    skip "CURL_FETCH_PUBLIC_BIN is only available in the Nix check"
  fi

  local public_script
  public_script="$(readlink -f "$CURL_FETCH_PUBLIC_BIN")"
  grep -E "^export SAFE_FETCH_CURL_BIN='/nix/store/.+-curl-.+/bin/curl'$" "$public_script"
  grep -F "unset QLOGDIR" "$public_script"
  grep -F "unset SSLKEYLOGFILE" "$public_script"

  run env \
    QLOGDIR=/tmp/untrusted-qlog \
    SSLKEYLOGFILE=/tmp/untrusted-keylog \
    "$CURL_FETCH_PUBLIC_BIN" --head

  [ "$status" -eq 2 ]
  [[ "$output" == *"no URL specified"* ]]
}
