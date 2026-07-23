#!/usr/bin/env bats
# Nix-built binary and host filesystem boundaries; exhaustive cases live in Rust tests.

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
  printf 'encrypted-blob\n' >"$SRC_ROOT/secrets/demo.conf"
  printf 'encrypted-yaml\n' >"$SRC_ROOT/secrets/ssh.yaml"

  STUB_DIR="$WORK/stub"
  SOPS_CALLS_FILE="$WORK/sops.calls"
  mkdir -p "$STUB_DIR"
  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/sops"
  cat >>"$STUB_DIR/sops" <<'EOF'
printf 'called\n' >>"$SOPS_STUB_CALLS_FILE"
for arg in "$@"; do
  if [ "$arg" = "--output-type" ]; then
    if [ "${SOPS_STUB_JSON_MODE:-valid}" = "malformed" ]; then
      printf '%s\n' '{"hosts":[{"host_unencrypted":"bad host","options":{}}]}'
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
EOF
  chmod +x "$STUB_DIR/sops"
}

teardown() {
  rm -rf "$WORK"
}

run_apply() {
  local manifest=$1
  shift
  printf '%s' "$manifest" >"$WORK/manifest.json"
  chmod 600 "$WORK/manifest.json"
  run env HOME="$FAKE_HOME" \
    APPLY_SECRETS_ROOT="$SRC_ROOT" \
    APPLY_SECRETS_MANIFEST="$WORK/manifest.json" \
    APPLY_SECRETS_SOPS_BIN="$STUB_DIR/sops" \
    SOPS_STUB_CALLS_FILE="$SOPS_CALLS_FILE" \
    "$APP" "$@"
}

mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

MANIFEST='[{"src":"secrets/demo.conf","dst":".ssh/config.d/50-demo.conf","mode":"600","dirMode":"700"}]'
SSH_MANIFEST='[{"src":"secrets/ssh.yaml","dst":".ssh/config.d/50-private.conf","format":"ssh-config-yaml","mode":"600","dirMode":"700"}]'

@test "Nix-built core writes raw output with secure modes under a restrictive umask" {
  mkdir "$FAKE_HOME/.ssh"
  chmod 755 "$FAKE_HOME/.ssh"
  umask 0777

  run_apply "$MANIFEST"

  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/50-demo.conf")" = "decrypted-content" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d/50-demo.conf")" = "600" ]
  [ "$(mode_of "$FAKE_HOME/.ssh/config.d")" = "700" ]
  [ "$(mode_of "$FAKE_HOME/.ssh")" = "755" ]
}

@test "Nix-built core renders a representative SSH secret" {
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

@test "dry-run does not start sops or create destination directories" {
  run_apply "$MANIFEST" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"would write"* ]]
  [ ! -e "$SOPS_CALLS_FILE" ]
  [ ! -e "$FAKE_HOME/.ssh" ]
}

@test "one rendering failure is soft and a later entry is still published" {
  mkdir -p "$FAKE_HOME/.ssh/config.d"
  printf 'keep\n' >"$FAKE_HOME/.ssh/config.d/first"
  export SOPS_STUB_JSON_MODE=malformed

  run_apply '[
    {"src":"secrets/ssh.yaml","dst":".ssh/config.d/first","format":"ssh-config-yaml","mode":"600","dirMode":"700"},
    {"src":"secrets/demo.conf","dst":".ssh/config.d/second","mode":"600","dirMode":"700"}
  ]'

  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/first")" = "keep" ]
  [ "$(cat "$FAKE_HOME/.ssh/config.d/second")" = "decrypted-content" ]
  [[ "$output" == *"decryption/rendering of secrets/ssh.yaml failed"* ]]
  [[ "$output" == *"1 file(s) skipped"* ]]
  [ "$(wc -l <"$SOPS_CALLS_FILE")" -eq 2 ]
}

@test "public app pins the repository manifest sops and Rust core" {
  if [[ -z ${APPLY_SECRETS_PUBLIC_BIN:-} ]]; then
    skip "APPLY_SECRETS_PUBLIC_BIN is only available in the Nix check"
  fi

  local public_script
  public_script="$(readlink -f "$APPLY_SECRETS_PUBLIC_BIN")"
  grep -E '^export APPLY_SECRETS_ROOT=/nix/store/.+-source$' "$public_script"
  grep -E '^export APPLY_SECRETS_MANIFEST=/nix/store/.+-secrets-manifest.json$' "$public_script"
  grep -E '^export APPLY_SECRETS_SOPS_BIN=/nix/store/.+-sops-.+/bin/sops$' "$public_script"
  grep -E '^exec /nix/store/.+-apply-secrets-0.1.0/bin/apply-secrets "\$@"$' "$public_script"

  run "$APPLY_SECRETS_PUBLIC_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply-secrets"* ]]
}
