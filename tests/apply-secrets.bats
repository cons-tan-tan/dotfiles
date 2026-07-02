#!/usr/bin/env bats
# apply-secrets 本体 (nix/apps/apply-secrets/apply-secrets.sh) の分岐テスト。
# sops をスタブし、HOME / ソースルート / マニフェストを fixture に差し替える。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  SCRIPT="$REPO_ROOT/nix/apps/apply-secrets/apply-secrets.sh"
  RENDERERS_DIR="$REPO_ROOT/nix/apps/apply-secrets/renderers"
  WORK="$(mktemp -d)"
  FAKE_HOME="$WORK/home"
  SRC_ROOT="$WORK/src"
  mkdir -p "$FAKE_HOME" "$SRC_ROOT/secrets"
  printf 'encrypted-blob\n' > "$SRC_ROOT/secrets/demo.conf"
  printf 'encrypted-yaml\n' > "$SRC_ROOT/secrets/ssh.yaml"

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  # sops スタブ: SOPS_STUB_FAIL=1 なら復号失敗を再現する
  cat > "$STUB_DIR/sops" <<'EOS'
#!/usr/bin/env bash
if [ "${SOPS_STUB_FAIL:-}" = "1" ]; then
  echo "stub: decryption failed" >&2
  exit 1
fi
for arg in "$@"; do
  if [ "$arg" = "--output-type" ]; then
    if [ "${SOPS_STUB_JSON_MODE:-valid}" = "malformed" ]; then
      cat <<'JSON'
{
  "hosts": [
    {
      "host_unencrypted": "bad host",
      "options": {
        "HostName": "192.0.2.10"
      }
    }
  ]
}
JSON
      exit 0
    fi
    cat <<'JSON'
{
  "hosts": [
    {
      "host_unencrypted": "work",
      "options": {
        "HostName": "192.0.2.10",
        "User": "alice",
        "Port": 2222
      }
    },
    {
      "patterns_unencrypted": ["lab", "lab.local"],
      "options": {
        "HostName": "lab.example.test",
        "User": "bob",
        "ForwardAgent": false,
        "ProxyJump": null
      }
    }
  ]
}
JSON
    exit 0
  fi
done
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
    APPLY_SECRETS_RENDERERS_DIR="$RENDERERS_DIR" \
    bash -eu -o pipefail "$SCRIPT" "$@"
}

# GNU (stat -c) と BSD (stat -f) の両対応
mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

assert_required_field_error() {
  local field=$1
  local manifest=$2

  run_apply "$manifest"

  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error"* ]]
  [[ "$output" == *"$field"* ]]
  [[ "$output" != *"decrypted-content"* ]]
}

MANIFEST='[{"src":"secrets/demo.conf","dst":".ssh/config.d/50-demo.conf","mode":"600","dirMode":"700"}]'
SSH_MANIFEST='[{"src":"secrets/ssh.yaml","dst":".ssh/config.d/50-private.conf","format":"ssh-config-yaml","mode":"600","dirMode":"700"}]'

@test "happy path writes file with mode 600 and dir 700" {
  run_apply "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/50-demo.conf")" = "decrypted-content" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d/50-demo.conf")" = "600" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d")" = "700" ]
}

@test "intermediate dirs created by apply-secrets are not world-accessible" {
  umask 022
  run_apply "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(mode_of "$FAKE_HOME/.ssh")" = "700" ]
}

@test "pre-existing parent dir permissions are left untouched" {
  mkdir -p "$FAKE_HOME/.ssh"
  chmod 755 "$FAKE_HOME/.ssh"
  run_apply "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(mode_of "$FAKE_HOME/.ssh")" = "755" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d")" = "700" ]
}

@test "dry-run lists target without writing" {
  run_apply "$MANIFEST" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would write"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-demo.conf" ]
}

@test "ssh-config-yaml renders structured secret to OpenSSH config" {
  run_apply "$SSH_MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/50-private.conf")" = "# Managed by apply-secrets - do not edit directly

Host work
    HostName 192.0.2.10
    User alice
    Port 2222

Host lab lab.local
    HostName lab.example.test
    User bob
    ForwardAgent no" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d/50-private.conf")" = "600" ]
}

@test "ssh-config-yaml renderer validates and renders JSON input" {
  run jq -r -f "$RENDERERS_DIR/ssh-config-yaml.jq" <<'JSON'
{
  "hosts": [
    {
      "host_unencrypted": "work",
      "options": {
        "HostName": "192.0.2.10",
        "User": "alice",
        "ForwardAgent": true
      }
    }
  ]
}
JSON
  [ "$status" -eq 0 ]
  [ "$output" = "# Managed by apply-secrets - do not edit directly

Host work
    HostName 192.0.2.10
    User alice
    ForwardAgent yes" ]
}

@test "ssh-config-yaml renderer rejects host pattern whitespace" {
  run jq -r -f "$RENDERERS_DIR/ssh-config-yaml.jq" <<'JSON'
{
  "hosts": [
    {
      "host_unencrypted": "bad host",
      "options": {
        "HostName": "192.0.2.10"
      }
    }
  ]
}
JSON
  [ "$status" -ne 0 ]
  [[ "$output" == *"without whitespace or control characters"* ]]
}

@test "ssh-config-yaml renderer rejects line breaks in option values" {
  run jq -r -f "$RENDERERS_DIR/ssh-config-yaml.jq" <<'JSON'
{
  "hosts": [
    {
      "host_unencrypted": "work",
      "options": {
        "HostName": "192.0.2.10\nHost injected"
      }
    }
  ]
}
JSON
  [ "$status" -ne 0 ]
  [[ "$output" == *"option values must not contain line breaks"* ]]
}

@test "ssh-config-yaml render failure skips and leaves no temp file" {
  export SOPS_STUB_JSON_MODE=malformed
  run_apply "$SSH_MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"decryption/rendering of secrets/ssh.yaml failed"* ]]
  [[ "$output" == *"1 file(s) skipped"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-private.conf" ]
  [ -z "$(find "$FAKE_HOME/.ssh/config.d" -name '50-private.conf.*' 2>/dev/null)" ]
}

@test "unsupported format is a manifest error" {
  run_apply '[{"src":"secrets/demo.conf","dst":".ssh/config.d/50-demo.conf","format":"nope","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error"* ]]
  [[ "$output" == *"unsupported format"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-demo.conf" ]
}

@test "missing source is a manifest error" {
  run_apply '[{"src":"secrets/nope.conf","dst":".ssh/config.d/50-nope.conf","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error"* ]]
  [[ "$output" == *"is not in the repo"* ]]
  [[ "$output" != *"decryption failed"* ]]
}

@test "dst missing is a manifest error and does not write HOME/null" {
  run_apply '[{"src":"secrets/demo.conf","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error"* ]]
  [[ "$output" == *"dst"* ]]
  [ ! -e "$FAKE_HOME/null" ]
}

@test "required manifest fields must be non-empty strings" {
  assert_required_field_error src '[{"dst":".ssh/config.d/50-demo.conf","mode":"600","dirMode":"700"}]'
  assert_required_field_error dst '[{"src":"secrets/demo.conf","dst":"","mode":"600","dirMode":"700"}]'
  assert_required_field_error mode '[{"src":"secrets/demo.conf","dst":".ssh/config.d/50-demo.conf","mode":null,"dirMode":"700"}]'
  assert_required_field_error dirMode '[{"src":"secrets/demo.conf","dst":".ssh/config.d/50-demo.conf","mode":"600"}]'
}

@test "decryption failure skips, reports, leaves no temp file, exits 0" {
  export SOPS_STUB_FAIL=1
  run_apply "$MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"decryption/rendering of secrets/demo.conf failed"* ]]
  [[ "$output" == *"1 file(s) skipped"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-demo.conf" ]
  # mktemp の残骸 (50-demo.conf.XXXXXX) が無いこと
  [ -z "$(find "$FAKE_HOME/.ssh/config.d" -name '50-demo.conf.*' 2>/dev/null)" ]
}

@test "dst escaping HOME is rejected" {
  run_apply '[{"src":"secrets/demo.conf","dst":"../evil.conf","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error"* ]]
  [[ "$output" == *"escapes HOME"* ]]
  [[ "$output" != *"decryption failed"* ]]
  [ ! -e "$WORK/evil.conf" ]
}
