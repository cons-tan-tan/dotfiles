#!/usr/bin/env bats
# Nix で build した apply-secrets を synthetic manifest と sops stub で検査する。

setup_file() {
  if [ -z "${APPLY_SECRETS_TEST_BIN:-}" ]; then
    echo "APPLY_SECRETS_TEST_BIN must be set to the built apply-secrets binary" >&2
    return 1
  fi
  if [[ "$APPLY_SECRETS_TEST_BIN" != /* ]]; then
    echo "APPLY_SECRETS_TEST_BIN must be an absolute path" >&2
    return 1
  fi
  if [ ! -x "$APPLY_SECRETS_TEST_BIN" ]; then
    echo "APPLY_SECRETS_TEST_BIN is not executable: $APPLY_SECRETS_TEST_BIN" >&2
    return 1
  fi
}

setup() {
  BASH_BIN="$(command -v bash)"
  APP="$APPLY_SECRETS_TEST_BIN"
  WORK="$(mktemp -d)"
  FAKE_HOME="$WORK/home"
  SRC_ROOT="$WORK/src"
  mkdir -p "$FAKE_HOME" "$SRC_ROOT/secrets"
  printf 'encrypted-blob\n' > "$SRC_ROOT/secrets/demo.conf"
  printf 'encrypted-yaml\n' > "$SRC_ROOT/secrets/ssh.yaml"

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  # sops スタブ: SOPS_STUB_FAIL=1 なら復号失敗を再現する
  printf '#!%s\n' "$BASH_BIN" > "$STUB_DIR/sops"
  cat >> "$STUB_DIR/sops" <<'EOS'
if [ "${SOPS_STUB_FAIL:-}" = "1" ]; then
  echo "stub: decryption failed" >&2
  exit 1
fi
for arg in "$@"; do
  if [ "$arg" = "--output-type" ]; then
    if [ -n "${SOPS_STUB_JSON_FILE:-}" ]; then
      cat "$SOPS_STUB_JSON_FILE"
      exit 0
    fi
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
}

teardown() {
  rm -rf "$WORK"
}

# manifest JSON を書いてbinaryを実行する共通helper
run_apply() {
  local manifest=$1
  shift
  printf '%s' "$manifest" > "$WORK/manifest.json"
  chmod 600 "$WORK/manifest.json"
  run env HOME="$FAKE_HOME" \
    APPLY_SECRETS_ROOT="$SRC_ROOT" \
    APPLY_SECRETS_MANIFEST="$WORK/manifest.json" \
    APPLY_SECRETS_SOPS_BIN="$STUB_DIR/sops" \
    "$APP" "$@"
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
  umask 0777
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
  cat > "$WORK/ssh.json" <<'JSON'
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
  export SOPS_STUB_JSON_FILE="$WORK/ssh.json"
  run_apply "$SSH_MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/50-private.conf")" = "# Managed by apply-secrets - do not edit directly

Host work
    HostName 192.0.2.10
    User alice
    ForwardAgent yes" ]
}

@test "ssh-config-yaml renderer rejects host pattern whitespace" {
  cat > "$WORK/ssh.json" <<'JSON'
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
  export SOPS_STUB_JSON_FILE="$WORK/ssh.json"
  run_apply "$SSH_MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"without whitespace or control characters"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-private.conf" ]
}

@test "ssh-config-yaml renderer rejects line breaks in option values" {
  cat > "$WORK/ssh.json" <<'JSON'
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
  export SOPS_STUB_JSON_FILE="$WORK/ssh.json"
  run_apply "$SSH_MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"option values must not contain line breaks"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-private.conf" ]
}

@test "ssh-config-yaml render failure skips and leaves no temp file" {
  export SOPS_STUB_JSON_MODE=malformed
  run_apply "$SSH_MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"decryption/rendering of secrets/ssh.yaml failed"* ]]
  [[ "$output" == *"1 file(s) skipped"* ]]
  [ ! -e "$FAKE_HOME/.ssh/config.d/50-private.conf" ]
  [ -z "$(find "$FAKE_HOME/.ssh/config.d" -type f 2>/dev/null)" ]
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
  [ -z "$(find "$FAKE_HOME/.ssh/config.d" -type f 2>/dev/null)" ]
}

@test "one rendering failure does not prevent later entries" {
  mkdir -p "$FAKE_HOME/.ssh/config.d"
  printf 'keep\n' > "$FAKE_HOME/.ssh/config.d/first"
  export SOPS_STUB_JSON_MODE=malformed
  run_apply '[
    {"src":"secrets/ssh.yaml","dst":".ssh/config.d/first","format":"ssh-config-yaml","mode":"600","dirMode":"700"},
    {"src":"secrets/demo.conf","dst":".ssh/config.d/second","mode":"600","dirMode":"700"}
  ]'
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/first")" = "keep" ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/second")" = "decrypted-content" ]
  [[ "$output" == *"1 file(s) skipped"* ]]
}

@test "dst escaping HOME is rejected" {
  run_apply '[{"src":"secrets/demo.conf","dst":"../evil.conf","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error"* ]]
  [[ "$output" == *"escapes HOME"* ]]
  [[ "$output" != *"decryption failed"* ]]
  [ ! -e "$WORK/evil.conf" ]
}

@test "malformed manifest is rejected before writing" {
  run_apply '[{"src":"secrets/demo.conf"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error: invalid JSON"* ]]
  [ ! -e "$FAKE_HOME/.ssh" ]
}

@test "non-array manifest is rejected before writing" {
  run_apply '{"src":"secrets/demo.conf"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifest error: invalid JSON"* ]]
  [ ! -e "$FAKE_HOME/.ssh" ]
}

@test "all entries are preflighted before any write" {
  run_apply '[
    {"src":"secrets/demo.conf","dst":".ssh/config.d/first","mode":"600","dirMode":"700"},
    {"src":"secrets/demo.conf","dst":"../escape","mode":"600","dirMode":"700"}
  ]'
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE_HOME/.ssh/config.d/first" ]
}

@test "invalid mode and duplicate destinations are rejected" {
  run_apply '[{"src":"secrets/demo.conf","dst":"out","mode":"68x","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"mode must be a 3- or 4-digit octal string"* ]]

  run_apply '[
    {"src":"secrets/demo.conf","dst":"out","mode":"600","dirMode":"700"},
    {"src":"secrets/demo.conf","dst":"out","mode":"600","dirMode":"700"}
  ]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate dst"* ]]
}

@test "source symlink is rejected" {
  ln -s "$SRC_ROOT/secrets/demo.conf" "$SRC_ROOT/secrets/link.conf"
  run_apply '[{"src":"secrets/link.conf","dst":"out","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"contains a symlink"* ]]
  [ ! -e "$FAKE_HOME/out" ]
}

@test "destination parent symlink is rejected without touching target" {
  mkdir -p "$WORK/outside"
  ln -s "$WORK/outside" "$FAKE_HOME/link"
  run_apply '[{"src":"secrets/demo.conf","dst":"link/private","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"contains a symlink"* ]]
  [ ! -e "$WORK/outside/private" ]
}

@test "destination symlink is rejected without touching target" {
  printf 'keep\n' > "$WORK/outside"
  ln -s "$WORK/outside" "$FAKE_HOME/private"
  run_apply '[{"src":"secrets/demo.conf","dst":"private","mode":"600","dirMode":"700"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"contains a symlink"* ]]
  [ "$(cat "$WORK/outside")" = "keep" ]
}

@test "dry-run still performs full preflight" {
  run_apply '[{"src":"secrets/nope","dst":"out","mode":"600","dirMode":"700"}]' --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not in the repo"* ]]
  [ ! -e "$FAKE_HOME/out" ]
}

@test "unknown option is a usage error" {
  run_apply "$MANIFEST" --unknown
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
  [ ! -e "$FAKE_HOME/.ssh" ]
}

@test "help does not hide an unknown option" {
  run_apply "$MANIFEST" --help --unknown
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
  [ ! -e "$FAKE_HOME/.ssh" ]
}
