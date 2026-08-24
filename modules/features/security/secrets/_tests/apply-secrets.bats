#!/usr/bin/env bats
# Nix-built binary and host filesystem boundaries; exhaustive cases live in Rust tests.

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup_file() {
  if [ -z "${APPLY_SECRETS_TEST_BIN:-}" ]; then
    return 0
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
  require_nix_fixture APPLY_SECRETS_TEST_BIN "built apply-secrets binary"

  BASH_BIN="$(command -v bash)"
  APP="$APPLY_SECRETS_TEST_BIN"
  WORK="$(mktemp -d)"
  FAKE_HOME="$WORK/home"
  SRC_ROOT="$WORK/src"
  mkdir -p "$FAKE_HOME" "$SRC_ROOT/secrets"
  printf 'encrypted-blob\n' >"$SRC_ROOT/secrets/demo.conf"

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/sops"
  cat >>"$STUB_DIR/sops" <<'EOF'
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
    "$APP" "$@"
}

mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

MANIFEST='[{"src":"secrets/demo.conf","dst":".ssh/config.d/50-demo.conf","mode":"600","dirMode":"700"}]'
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

  run env HOME="$FAKE_HOME" "$APPLY_SECRETS_PUBLIC_BIN" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would write"* ]]
  [ ! -e "$FAKE_HOME/.ssh" ]
}
