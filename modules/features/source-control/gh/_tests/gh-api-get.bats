#!/usr/bin/env bats
# Nix package/process boundaries only; the complete option policy lives in Rust tests.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_lib/bats/test-helper.bash"

setup_file() {
  bats_require_minimum_version 1.5.0

  if [[ -z ${GH_API_GET_TEST_BIN:-} ]]; then
    return 0
  fi
  case "$GH_API_GET_TEST_BIN" in
  /*) ;;
  *)
    echo "GH_API_GET_TEST_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  if [[ ! -x $GH_API_GET_TEST_BIN ]]; then
    echo "GH_API_GET_TEST_BIN is not executable: $GH_API_GET_TEST_BIN" >&2
    return 1
  fi
}

setup() {
  require_nix_fixture GH_API_GET_TEST_BIN "unwrapped gh-api-get binary"

  BASH_BIN="$(command -v bash)"
  STUB_DIR="$(mktemp -d)"
  GH_STUB="$STUB_DIR/gh"
  printf '#!%s\n' "$BASH_BIN" >"$GH_STUB"
  cat >>"$GH_STUB" <<'EOF'
if [[ ${GH_STUB_PRINT_ARGS:-1} == 1 ]]; then
  printf '<%s>\n' "$@"
fi
printf '%s' "${GH_STUB_STDOUT:-}"
printf '%s' "${GH_STUB_STDERR:-}" >&2
exit "${GH_STUB_EXIT:-0}"
EOF
  chmod +x "$GH_STUB"
}

teardown() {
  rm -rf "$STUB_DIR"
}

run_gh_api_get() {
  run env SAFE_FETCH_GH_BIN="$GH_STUB" "$GH_API_GET_TEST_BIN" "$@"
}

@test "relative endpoint reaches github.com with forced GET" {
  run_gh_api_get repos/o/r/issues -F state=open --jq .

  [ "$status" -eq 0 ]
  [ "$output" = "<api>
<--hostname>
<github.com>
<repos/o/r/issues>
<-F>
<state=open>
<--jq>
<.>
<--method>
<GET>" ]
}

@test "endpoint repository placeholder exits 2 without invoking the child" {
  run_gh_api_get 'repos/{owner}/r'

  [ "$status" -eq 2 ]
  [[ "$output" == *"local repository metadata"* ]]
  [[ "$output" != *"<api>"* ]]
}

@test "child stdout stderr and exit status are preserved" {
  run --separate-stderr env \
    GH_STUB_PRINT_ARGS=0 \
    GH_STUB_STDOUT="fixture stdout" \
    GH_STUB_STDERR="fixture stderr" \
    GH_STUB_EXIT=43 \
    SAFE_FETCH_GH_BIN="$GH_STUB" \
    "$GH_API_GET_TEST_BIN" repos/o/r

  [ "$status" -eq 43 ]
  [ "$output" = "fixture stdout" ]
  [ "$stderr" = "fixture stderr" ]
}

@test "extension root keeps the gh extension executable contract" {
  if [[ -z ${GH_API_GET_EXTENSION_ROOT:-} ]]; then
    skip "GH_API_GET_EXTENSION_ROOT is only available in the Nix check"
  fi

  [ -L "$GH_API_GET_EXTENSION_ROOT/gh-api-get" ]
  [ -x "$GH_API_GET_EXTENSION_ROOT/gh-api-get" ]

  run env GH_STUB_EXIT=88 SAFE_FETCH_GH_BIN="$GH_STUB" \
    "$GH_API_GET_EXTENSION_ROOT/gh-api-get" --help
  [ "$status" -eq 0 ]
}

@test "public wrapper ignores a caller-provided child override" {
  if [[ -z ${GH_API_GET_PUBLIC_BIN:-} ]]; then
    skip "GH_API_GET_PUBLIC_BIN is only available in the Nix check"
  fi

  run env GH_STUB_EXIT=88 SAFE_FETCH_GH_BIN="$GH_STUB" \
    "$GH_API_GET_PUBLIC_BIN" --help
  [ "$status" -eq 0 ]
}
