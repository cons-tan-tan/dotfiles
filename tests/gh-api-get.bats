#!/usr/bin/env bats
# gh-api-get の Rust policy と固定 GET argv を、ネットワークに出ない stub gh で検査する。

setup_file() {
  if [[ -z ${GH_API_GET_TEST_BIN:-} ]]; then
    echo "GH_API_GET_TEST_BIN must identify the unwrapped gh-api-get binary" >&2
    return 1
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
  BASH_BIN="$(command -v bash)"
  STUB_DIR="$(mktemp -d)"
  GH_STUB="$STUB_DIR/gh"
  printf '#!%s\n' "$BASH_BIN" >"$GH_STUB"
  cat >>"$GH_STUB" <<'EOF'
printf '<%s>\n' "$@"
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

@test "allowed fields pass through and force GET" {
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

@test "documented response options pass through" {
  run_gh_api_get repos/o/r --include --paginate --silent --slurp \
    --hostname github.com --preview nebula --template '{{.id}}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"<--method>"* ]]
  [[ "$output" == *"<GET>"* ]]
}

@test "short attached literal fields pass through" {
  run_gh_api_get repos/o/r -Fstate=open -fper_page=10 -q.id -pnebula -t'{{.id}}'

  [ "$status" -eq 0 ]
}

@test "--method value is rejected" {
  run_gh_api_get repos/o/r --method DELETE
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "--method=value is rejected" {
  run_gh_api_get repos/o/r --method=DELETE
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "-X value is rejected" {
  run_gh_api_get repos/o/r -X DELETE
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "-XVALUE is rejected" {
  run_gh_api_get repos/o/r -XDELETE
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "--input value is rejected" {
  run_gh_api_get repos/o/r --input /tmp/body
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "--input=value is rejected" {
  run_gh_api_get repos/o/r --input=/tmp/body
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "bare -- is rejected" {
  run_gh_api_get repos/o/r -- --method DELETE
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "typed field file indirection is rejected" {
  run_gh_api_get repos/o/r --field body=@/tmp/body
  [ "$status" -eq 2 ]
  [[ "$output" == *"local files"* ]]
}

@test "raw field stdin indirection is rejected" {
  run_gh_api_get repos/o/r --raw-field body=@-
  [ "$status" -eq 2 ]
  [[ "$output" == *"standard input"* ]]
}

@test "field without key value syntax is rejected" {
  run_gh_api_get repos/o/r -F body
  [ "$status" -eq 2 ]
  [[ "$output" == *"key=value"* ]]
}

@test "unknown option is rejected" {
  run_gh_api_get repos/o/r --cache 1h
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive read-only allowlist"* ]]
}

@test "method override header is rejected" {
  run_gh_api_get repos/o/r -H "X-HTTP-Method-Override: DELETE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"override"* ]]
}

@test "absolute endpoint is rejected" {
  run_gh_api_get https://example.com/repos/o/r
  [ "$status" -eq 2 ]
  [[ "$output" == *"relative GitHub API endpoint"* ]]
}

@test "uppercase absolute endpoint is rejected" {
  run_gh_api_get HTTPS://example.com/repos/o/r
  [ "$status" -eq 2 ]
  [[ "$output" == *"relative GitHub API endpoint"* ]]
}

@test "scheme-relative endpoint is rejected" {
  run_gh_api_get //example.com/repos/o/r
  [ "$status" -eq 2 ]
  [[ "$output" == *"relative GitHub API endpoint"* ]]
}

@test "metadata service endpoint is rejected" {
  run_gh_api_get http://169.254.169.254/latest/meta-data
  [ "$status" -eq 2 ]
  [[ "$output" == *"relative GitHub API endpoint"* ]]
}

@test "untrusted hostname is rejected" {
  run_gh_api_get repos/o/r --hostname example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *"only github.com"* ]]
}

@test "field repository placeholders are rejected" {
  run_gh_api_get repos/o/r --raw-field 'owner={owner}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"local repository metadata"* ]]
}

@test "jq environment builtin is rejected" {
  run_gh_api_get repos/o/r --jq 'env.GH_TOKEN'
  [ "$status" -eq 2 ]
  [[ "$output" == *"environment access"* ]]
  [[ "$output" != *"GH_TOKEN"* ]]
}

@test "jq ENV variable is rejected" {
  run_gh_api_get repos/o/r -q'$ENV.GH_TOKEN'
  [ "$status" -eq 2 ]
  [[ "$output" == *"environment access"* ]]
  [[ "$output" != *"GH_TOKEN"* ]]
}

@test "multiple endpoints are rejected" {
  run_gh_api_get repos/o/r repos/o/other
  [ "$status" -eq 2 ]
  [[ "$output" == *"exactly one"* ]]
}

@test "missing endpoint is rejected" {
  run_gh_api_get --paginate
  [ "$status" -eq 2 ]
  [[ "$output" == *"exactly one"* ]]
}

@test "bare help is allowed" {
  run_gh_api_get --help
  [ "$status" -eq 0 ]
}

@test "gh exit status is preserved" {
  run env GH_STUB_EXIT=43 SAFE_FETCH_GH_BIN="$GH_STUB" \
    "$GH_API_GET_TEST_BIN" repos/o/r
  [ "$status" -eq 43 ]
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

@test "public wrapper ignores caller child override" {
  if [[ -z ${GH_API_GET_PUBLIC_BIN:-} ]]; then
    skip "GH_API_GET_PUBLIC_BIN is only available in the Nix check"
  fi

  run env GH_STUB_EXIT=88 SAFE_FETCH_GH_BIN="$GH_STUB" \
    "$GH_API_GET_PUBLIC_BIN" --help
  [ "$status" -eq 0 ]
}
