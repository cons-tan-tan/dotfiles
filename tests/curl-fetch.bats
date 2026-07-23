#!/usr/bin/env bats
# curl-fetch の Rust policy と固定 argv を、ネットワークに出ない stub curl で検査する。

setup_file() {
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
printf '<%s>\n' "$@"
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

assert_allowed() {
  [ "$status" -eq 0 ]
  [[ "$output" == *"<-q>"* ]]
}

@test "plain GET passes through with pinned protocol arguments" {
  run_curl_fetch -sL https://example.com

  assert_allowed
  [ "$output" = "<-q>
<--globoff>
<--proto>
<=http,https>
<--proto-redir>
<=http,https>
<-sL>
<https://example.com>" ]
}

@test "documented fallback command passes through" {
  run_curl_fetch -fsSL -A "claude-code/1.0" https://example.com
  assert_allowed
}

@test "documented FxEmbed command passes through" {
  run_curl_fetch -sSL --fail-with-body https://example.com
  assert_allowed
}

@test "long form fallback command passes through" {
  run_curl_fetch --silent --location --user-agent "claude-code/1.0" https://example.com
  assert_allowed
}

@test "timeout and retry flags pass through" {
  run_curl_fetch --max-time 10 --connect-timeout 5 --retry 2 https://example.com
  assert_allowed
}

@test "literal header passes through" {
  run_curl_fetch -H "Accept: text/html" https://example.com
  assert_allowed
}

@test "--url https URL passes through" {
  run_curl_fetch --url https://example.com
  assert_allowed
}

@test "--url=https URL passes through" {
  run_curl_fetch --url=https://example.com
  assert_allowed
}

@test "-I HEAD request passes through" {
  run_curl_fetch -I https://example.com
  assert_allowed
}

@test "-i show headers passes through" {
  run_curl_fetch -i https://example.com
  assert_allowed
}

@test "--globoff passes through" {
  run_curl_fetch --globoff "https://example.com/path[1]"
  assert_allowed
}

@test "-o explicit output path passes through" {
  run_curl_fetch -o /tmp/output.html https://example.com
  assert_allowed
}

@test "-O is denied" {
  run_curl_fetch -O https://example.com/payload
  [ "$status" -eq 1 ]
  [[ "$output" == *"Reason:"* ]]
  [[ "$output" == *"Alternative:"* ]]
}

@test "combined -sLo explicit output path passes through" {
  run_curl_fetch -sLo /tmp/output.html https://example.com
  assert_allowed
}

@test "--output explicit output path passes through" {
  run_curl_fetch --output /tmp/output.html https://example.com
  assert_allowed
}

@test "--output=file explicit output path passes through" {
  run_curl_fetch --output=/tmp/output.html https://example.com
  assert_allowed
}

@test "--remote-name is denied" {
  run_curl_fetch --remote-name https://example.com/payload
  [ "$status" -eq 1 ]
}

@test "-J is denied" {
  run_curl_fetch -OJ https://example.com
  [ "$status" -eq 1 ]
}

@test "-D is denied" {
  run_curl_fetch -D /tmp/headers https://example.com
  [ "$status" -eq 1 ]
}

@test "--dump-header is denied" {
  run_curl_fetch --dump-header /tmp/headers https://example.com
  [ "$status" -eq 1 ]
}

@test "-c is denied" {
  run_curl_fetch -c /tmp/jar https://example.com
  [ "$status" -eq 1 ]
}

@test "--cookie-jar is denied" {
  run_curl_fetch --cookie-jar /tmp/jar https://example.com
  [ "$status" -eq 1 ]
}

@test "--trace is denied" {
  run_curl_fetch --trace /tmp/trace https://example.com
  [ "$status" -eq 1 ]
}

@test "--etag-save is denied" {
  run_curl_fetch --etag-save /tmp/etag https://example.com
  [ "$status" -eq 1 ]
}

@test "--libcurl is denied" {
  run_curl_fetch --libcurl /tmp/evil.c https://example.com
  [ "$status" -eq 1 ]
}

@test "--libcurl=file is denied" {
  run_curl_fetch --libcurl=/tmp/evil.c https://example.com
  [ "$status" -eq 1 ]
}

@test "--hsts is denied" {
  run_curl_fetch --hsts /tmp/evil https://example.com
  [ "$status" -eq 1 ]
}

@test "--alt-svc is denied" {
  run_curl_fetch --alt-svc /tmp/evil https://example.com
  [ "$status" -eq 1 ]
}

@test "--stderr is denied" {
  run_curl_fetch --stderr /tmp/log https://example.com
  [ "$status" -eq 1 ]
}

@test "--ssl-sessions is denied" {
  run_curl_fetch --ssl-sessions /tmp/sessions https://example.com
  [ "$status" -eq 1 ]
}

@test "--variable @file is denied" {
  run_curl_fetch --variable name=@/etc/passwd https://example.com
  [ "$status" -eq 1 ]
}

@test "--write-out literal format passes through" {
  run_curl_fetch --write-out "%{http_code}" https://example.com
  assert_allowed
}

@test "--write-out @file is denied with guidance" {
  run_curl_fetch --write-out @/etc/passwd https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"@file syntax reads a local format string"* ]]
  [[ "$output" == *"Alternative:"* ]]
}

@test "-w @file is denied with guidance" {
  run_curl_fetch -w @/etc/passwd https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"@file syntax reads a local format string"* ]]
  [[ "$output" == *"Alternative:"* ]]
}

@test "--write-out output directive is denied" {
  run_curl_fetch --write-out "%output{/tmp/status}%{http_code}" https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"%output{"* ]]
}

@test "--write-out append output directive is denied" {
  run_curl_fetch --write-out "%output{>>/tmp/status}%{http_code}" https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"%output{"* ]]
}

@test "unknown long flag is denied" {
  run_curl_fetch --cacert /tmp/ca.pem https://example.com
  [ "$status" -eq 1 ]
}

@test "bare file URL is denied" {
  run_curl_fetch file:///etc/passwd
  [ "$status" -eq 1 ]
}

@test "bare ftp URL is denied" {
  run_curl_fetch ftp://example.com/file
  [ "$status" -eq 1 ]
}

@test "--url=file URL is denied" {
  run_curl_fetch --url=file:///etc/passwd
  [ "$status" -eq 1 ]
}

@test "--url file URL is denied" {
  run_curl_fetch --url file:///etc/passwd
  [ "$status" -eq 1 ]
}

@test "-X is denied (regression)" {
  run_curl_fetch -X POST https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"read-only fetch"* ]]
}

@test "--data is denied (regression)" {
  run_curl_fetch --data foo https://example.com
  [ "$status" -eq 1 ]
}

@test "bare -- is denied (regression)" {
  run_curl_fetch -- https://example.com
  [ "$status" -eq 1 ]
}

@test "header @file is denied (regression)" {
  run_curl_fetch -H @/etc/passwd https://example.com
  [ "$status" -eq 1 ]
}

@test "header control characters are denied" {
  run_curl_fetch --header $'X-Test: ok\r\nX-HTTP-Method-Override: DELETE' https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"control characters"* ]]
}

@test "method override header is denied" {
  run_curl_fetch --header "X-HTTP-Method-Override: DELETE" https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"read-only GET"* ]]
}

@test "framing header is denied" {
  run_curl_fetch --header "Transfer-Encoding: chunked" https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"framing headers"* ]]
}

@test "user agent cannot inject a header" {
  run_curl_fetch --user-agent $'safe\r\nX-HTTP-Method-Override: POST' https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"control characters"* ]]
}

@test "missing option value is denied" {
  run_curl_fetch --header
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "curl exit status is preserved" {
  run env CURL_STUB_EXIT=42 SAFE_FETCH_CURL_BIN="$CURL_STUB" \
    "$CURL_FETCH_TEST_BIN" https://example.com
  [ "$status" -eq 42 ]
}

@test "public wrapper ignores caller child override" {
  if [[ -z ${CURL_FETCH_PUBLIC_BIN:-} ]]; then
    skip "CURL_FETCH_PUBLIC_BIN is only available in the Nix check"
  fi

  run env CURL_STUB_EXIT=88 SAFE_FETCH_CURL_BIN="$CURL_STUB" \
    "$CURL_FETCH_PUBLIC_BIN" --head
  [ "$status" -eq 2 ]
  [[ "$output" == *"no URL specified"* ]]

  grep -F "unset QLOGDIR" "$CURL_FETCH_PUBLIC_BIN"
  grep -F "unset SSLKEYLOGFILE" "$CURL_FETCH_PUBLIC_BIN"
}
