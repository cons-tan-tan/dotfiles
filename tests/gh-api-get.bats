#!/usr/bin/env bats
# gh-api-get wrapper の argv 検査ロジックを、ネットワークに出ない stub gh で検査する。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  SCRIPT="$REPO_ROOT/nix/packages/gh-api-get/gh-api-get.sh"
  BASH_BIN="$(command -v bash)"
  STUB_DIR="$(mktemp -d)"
  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/gh"
  cat >>"$STUB_DIR/gh" <<'EOF'
printf '<%s>\n' "$@"
EOF
  chmod +x "$STUB_DIR/gh"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "allowed fields pass through and force GET" {
  run bash "$SCRIPT" repos/o/r/issues -F state=open --jq .

  [ "$status" -eq 0 ]
  [ "$output" = "<api>
<repos/o/r/issues>
<-F>
<state=open>
<--jq>
<.>
<--method>
<GET>" ]
}

@test "--method value is rejected" {
  run bash "$SCRIPT" repos/o/r --method DELETE

  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "--method=value is rejected" {
  run bash "$SCRIPT" repos/o/r --method=DELETE

  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "-X value is rejected" {
  run bash "$SCRIPT" repos/o/r -X DELETE

  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "-XVALUE is rejected" {
  run bash "$SCRIPT" repos/o/r -XDELETE

  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "bare -- is rejected" {
  run bash "$SCRIPT" repos/o/r -- --method DELETE

  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed"* ]]
}
