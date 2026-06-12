#!/usr/bin/env bats
# apply-secrets 本体 (nix/apps/apply-secrets.sh) の分岐テスト。
# sops をスタブし、HOME / ソースルート / マニフェストを fixture に差し替える。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  SCRIPT="$REPO_ROOT/nix/apps/apply-secrets.sh"
  WORK="$(mktemp -d)"
  FAKE_HOME="$WORK/home"
  SRC_ROOT="$WORK/src"
  mkdir -p "$FAKE_HOME" "$SRC_ROOT/secrets"
  printf 'encrypted-blob\n' > "$SRC_ROOT/secrets/demo.conf"

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  # sops スタブ: SOPS_STUB_FAIL=1 なら復号失敗を再現する
  cat > "$STUB_DIR/sops" <<'EOS'
#!/usr/bin/env bash
if [ "${SOPS_STUB_FAIL:-}" = "1" ]; then
  echo "stub: decryption failed" >&2
  exit 1
fi
echo "decrypted-content"
EOS
  chmod +x "$STUB_DIR/sops"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$WORK"
}

# manifest JSON を書いてスクリプトを実行する共通ヘルパ
run_apply() {
  local manifest=$1
  shift
  printf '%s' "$manifest" > "$WORK/manifest.json"
  run env HOME="$FAKE_HOME" \
    APPLY_SECRETS_ROOT="$SRC_ROOT" \
    APPLY_SECRETS_MANIFEST="$WORK/manifest.json" \
    bash -eu -o pipefail "$SCRIPT" "$@"
}

# GNU (stat -c) と BSD (stat -f) の両対応
mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

MANIFEST='[{"src":"secrets/demo.conf","dst":".ssh/config.d/50-demo.conf","mode":"600","dirMode":"700"}]'

@test "happy path writes file with mode 600 and dir 700" {
  run_apply "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/50-demo.conf")" = "decrypted-content" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d/50-demo.conf")" = "600" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d")" = "700" ]
}

@test "dry-run lists target without writing" {
  run_apply "$MANIFEST" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would write"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-demo.conf" ]
}

@test "missing source is skipped without failure" {
  run_apply '[{"src":"secrets/nope.conf","dst":".ssh/config.d/50-nope.conf","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not in the repo; skipping"* ]]
}

@test "decryption failure skips, reports, leaves no temp file, exits 0" {
  export SOPS_STUB_FAIL=1
  run_apply "$MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"decryption of secrets/demo.conf failed"* ]]
  [[ "$output" == *"1 file(s) skipped"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-demo.conf" ]
  # mktemp の残骸 (50-demo.conf.XXXXXX) が無いこと
  [ -z "$(find "$FAKE_HOME/.ssh/config.d" -name '50-demo.conf.*' 2>/dev/null)" ]
}

@test "dst escaping HOME is rejected" {
  run_apply '[{"src":"secrets/demo.conf","dst":"../evil.conf","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"escapes HOME; skipping"* ]]
  [ ! -e "$WORK/evil.conf" ]
}
