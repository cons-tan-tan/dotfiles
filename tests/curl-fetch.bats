#!/usr/bin/env bats
# curl-fetch のフラグ検査ロジックのテスト。ネットワークに出ないよう
# PATH 先頭のスタブ curl に差し替えて実行する。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  SCRIPT="$REPO_ROOT/nix/modules/home/programs/curl-fetch.sh"
  STUB_DIR="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho curl-stub-called\n' > "$STUB_DIR/curl"
  chmod +x "$STUB_DIR/curl"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "plain GET passes through" {
  run bash "$SCRIPT" -sL https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "documented fallback command passes through" {
  run bash "$SCRIPT" -sL -A "claude-code/1.0" https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "long form fallback command passes through" {
  run bash "$SCRIPT" --silent --location --user-agent "claude-code/1.0" https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "timeout and retry flags pass through" {
  run bash "$SCRIPT" --max-time 10 --connect-timeout 5 --retry 2 https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "literal header passes through" {
  run bash "$SCRIPT" -H "Accept: text/html" https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "--url https URL passes through" {
  run bash "$SCRIPT" --url https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "--url=https URL passes through" {
  run bash "$SCRIPT" --url=https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "-I HEAD request passes through" {
  run bash "$SCRIPT" -I https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "-i show headers passes through" {
  run bash "$SCRIPT" -i https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "--globoff passes through" {
  run bash "$SCRIPT" --globoff "https://example.com/path[1]"
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "-o explicit output path passes through" {
  run bash "$SCRIPT" -o /tmp/output.html https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "-O is denied" {
  run bash "$SCRIPT" -O https://example.com/payload
  [ "$status" -eq 1 ]
  [[ "$output" == *"Reason:"* ]]
  [[ "$output" == *"Alternative:"* ]]
}

@test "combined -sLo explicit output path passes through" {
  run bash "$SCRIPT" -sLo /tmp/output.html https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "--output explicit output path passes through" {
  run bash "$SCRIPT" --output /tmp/output.html https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "--output=file explicit output path passes through" {
  run bash "$SCRIPT" --output=/tmp/output.html https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "--remote-name is denied" {
  run bash "$SCRIPT" --remote-name https://example.com/payload
  [ "$status" -eq 1 ]
}

@test "-J is denied" {
  run bash "$SCRIPT" -OJ https://example.com
  [ "$status" -eq 1 ]
}

@test "-D is denied" {
  run bash "$SCRIPT" -D /tmp/headers https://example.com
  [ "$status" -eq 1 ]
}

@test "--dump-header is denied" {
  run bash "$SCRIPT" --dump-header /tmp/headers https://example.com
  [ "$status" -eq 1 ]
}

@test "-c is denied" {
  run bash "$SCRIPT" -c /tmp/jar https://example.com
  [ "$status" -eq 1 ]
}

@test "--cookie-jar is denied" {
  run bash "$SCRIPT" --cookie-jar /tmp/jar https://example.com
  [ "$status" -eq 1 ]
}

@test "--trace is denied" {
  run bash "$SCRIPT" --trace /tmp/trace https://example.com
  [ "$status" -eq 1 ]
}

@test "--etag-save is denied" {
  run bash "$SCRIPT" --etag-save /tmp/etag https://example.com
  [ "$status" -eq 1 ]
}

@test "--libcurl is denied" {
  run bash "$SCRIPT" --libcurl /tmp/evil.c https://example.com
  [ "$status" -eq 1 ]
}

@test "--libcurl=file is denied" {
  run bash "$SCRIPT" --libcurl=/tmp/evil.c https://example.com
  [ "$status" -eq 1 ]
}

@test "--hsts is denied" {
  run bash "$SCRIPT" --hsts /tmp/evil https://example.com
  [ "$status" -eq 1 ]
}

@test "--alt-svc is denied" {
  run bash "$SCRIPT" --alt-svc /tmp/evil https://example.com
  [ "$status" -eq 1 ]
}

@test "--stderr is denied" {
  run bash "$SCRIPT" --stderr /tmp/log https://example.com
  [ "$status" -eq 1 ]
}

@test "--ssl-sessions is denied" {
  run bash "$SCRIPT" --ssl-sessions /tmp/sessions https://example.com
  [ "$status" -eq 1 ]
}

@test "--variable @file is denied" {
  run bash "$SCRIPT" --variable name=@/etc/passwd https://example.com
  [ "$status" -eq 1 ]
}

@test "--write-out literal format passes through" {
  run bash "$SCRIPT" --write-out "%{http_code}" https://example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl-stub-called"* ]]
}

@test "--write-out @file is denied with guidance" {
  run bash "$SCRIPT" --write-out @/etc/passwd https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"@file syntax reads a local format string"* ]]
  [[ "$output" == *"Alternative:"* ]]
}

@test "-w @file is denied with guidance" {
  run bash "$SCRIPT" -w @/etc/passwd https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"@file syntax reads a local format string"* ]]
  [[ "$output" == *"Alternative:"* ]]
}

@test "unknown long flag is denied" {
  run bash "$SCRIPT" --cacert /tmp/ca.pem https://example.com
  [ "$status" -eq 1 ]
}

@test "bare file URL is denied" {
  run bash "$SCRIPT" file:///etc/passwd
  [ "$status" -eq 1 ]
}

@test "bare ftp URL is denied" {
  run bash "$SCRIPT" ftp://example.com/file
  [ "$status" -eq 1 ]
}

@test "--url=file URL is denied" {
  run bash "$SCRIPT" --url=file:///etc/passwd
  [ "$status" -eq 1 ]
}

@test "--url file URL is denied" {
  run bash "$SCRIPT" --url file:///etc/passwd
  [ "$status" -eq 1 ]
}

# 既存挙動のリグレッション確認
@test "-X is denied (regression)" {
  run bash "$SCRIPT" -X POST https://example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"read-only fetch"* ]]
}

@test "--data is denied (regression)" {
  run bash "$SCRIPT" --data foo https://example.com
  [ "$status" -eq 1 ]
}

@test "bare -- is denied (regression)" {
  run bash "$SCRIPT" -- https://example.com
  [ "$status" -eq 1 ]
}

@test "header @file is denied (regression)" {
  run bash "$SCRIPT" -H @/etc/passwd https://example.com
  [ "$status" -eq 1 ]
}
