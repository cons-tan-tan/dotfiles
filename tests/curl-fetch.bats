#!/usr/bin/env bats
# Nix package/process boundaries only; the complete option policy lives in Rust tests.

setup_file() {
  bats_require_minimum_version 1.5.0

  if [[ -z ${CURL_FETCH_TEST_BIN:-} ]]; then
    echo "CURL_FETCH_TEST_BIN must identify the unwrapped curl-fetch binary" >&2
    return 1
  fi
  case "$CURL_FETCH_TEST_BIN" in
  /*) ;;
  *)
    echo "CURL_FETCH_TEST_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  if [[ ! -x $CURL_FETCH_TEST_BIN ]]; then
    echo "CURL_FETCH_TEST_BIN is not executable: $CURL_FETCH_TEST_BIN" >&2
    return 1
  fi
}

setup() {
  BASH_BIN="$(command -v bash)"
  STUB_DIR="$(mktemp -d)"
  CURL_STUB="$STUB_DIR/curl"
  printf '#!%s\n' "$BASH_BIN" >"$CURL_STUB"
  cat >>"$CURL_STUB" <<'EOF'
if [[ ${CURL_STUB_PRINT_ARGS:-1} == 1 ]]; then
  printf '<%s>\n' "$@"
fi
printf '%s' "${CURL_STUB_STDOUT:-}"
printf '%s' "${CURL_STUB_STDERR:-}" >&2
exit "${CURL_STUB_EXIT:-0}"
EOF
  chmod +x "$CURL_STUB"
}

teardown() {
  rm -rf "$STUB_DIR"
}

run_curl_fetch() {
  run env SAFE_FETCH_CURL_BIN="$CURL_STUB" "$CURL_FETCH_TEST_BIN" "$@"
}

@test "plain GET reaches the child with the pinned protocol prefix" {
  run_curl_fetch -sL https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = "<-q>
<--globoff>
<--proto>
<=http,https>
<--proto-redir>
<=http,https>
<-sL>
<https://example.com>" ]
}

@test "policy rejection exits 1 without invoking the child" {
  run_curl_fetch --request POST https://example.com

  [ "$status" -eq 1 ]
  [[ "$output" == *"Reason:"* ]]
  [[ "$output" == *"Alternative:"* ]]
  [[ "$output" != *"<-q>"* ]]
}

@test "child stdout stderr and exit status are preserved" {
  run --separate-stderr env \
    CURL_STUB_PRINT_ARGS=0 \
    CURL_STUB_STDOUT="fixture stdout" \
    CURL_STUB_STDERR="fixture stderr" \
    CURL_STUB_EXIT=42 \
    SAFE_FETCH_CURL_BIN="$CURL_STUB" \
    "$CURL_FETCH_TEST_BIN" https://example.com

  [ "$status" -eq 42 ]
  [ "$output" = "fixture stdout" ]
  [ "$stderr" = "fixture stderr" ]
}

@test "public wrapper fixes the child and clears key logging environments" {
  if [[ -z ${CURL_FETCH_PUBLIC_BIN:-} ]]; then
    skip "CURL_FETCH_PUBLIC_BIN is only available in the Nix check"
  fi

  run env \
    CURL_STUB_EXIT=88 \
    QLOGDIR=/tmp/untrusted-qlog \
    SSLKEYLOGFILE=/tmp/untrusted-keylog \
    SAFE_FETCH_CURL_BIN="$CURL_STUB" \
    "$CURL_FETCH_PUBLIC_BIN" --head

  [ "$status" -eq 2 ]
  [[ "$output" == *"no URL specified"* ]]
  grep -F "unset QLOGDIR" "$CURL_FETCH_PUBLIC_BIN"
  grep -F "unset SSLKEYLOGFILE" "$CURL_FETCH_PUBLIC_BIN"
}
