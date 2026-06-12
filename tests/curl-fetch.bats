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

@test "-o is denied" {
  run bash "$SCRIPT" -o /tmp/evil https://example.com
  [ "$status" -eq 1 ]
}

@test "-O is denied" {
  run bash "$SCRIPT" -O https://example.com/payload
  [ "$status" -eq 1 ]
}

@test "combined -sLo is denied" {
  run bash "$SCRIPT" -sLo /tmp/evil https://example.com
  [ "$status" -eq 1 ]
}

@test "--output is denied" {
  run bash "$SCRIPT" --output /tmp/evil https://example.com
  [ "$status" -eq 1 ]
}

@test "--output=file is denied" {
  run bash "$SCRIPT" --output=/tmp/evil https://example.com
  [ "$status" -eq 1 ]
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

# 既存挙動のリグレッション確認
@test "-X is denied (regression)" {
  run bash "$SCRIPT" -X POST https://example.com
  [ "$status" -eq 1 ]
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
