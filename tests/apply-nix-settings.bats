#!/usr/bin/env bats
# apply-nix-settings の managed block 更新を、/etc ではなく一時ファイルで検査する。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  SCRIPT="$REPO_ROOT/nix/apps/apply-nix-settings.sh"
  WORK="$(mktemp -d)"
  STUB_DIR="$WORK/stub"
  TARGET="$WORK/nix.custom.conf"
  SNIPPET="$WORK/snippet.conf"
  cat >"$SNIPPET" <<'EOF'
extra-trusted-users = constantan
extra-substituters = https://cache.numtide.com
extra-trusted-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
EOF
}

teardown() {
  rm -rf "$WORK"
}

run_apply() {
  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    bash -eu -o pipefail "$SCRIPT" "$@"
}

run_apply_with_nix_conf() {
  local nix_conf=$1
  shift
  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_NIX_CONF="$nix_conf" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    bash -eu -o pipefail "$SCRIPT" "$@"
}

@test "creates managed block while preserving existing content" {
  cat >"$TARGET" <<'EOF'
# unmanaged line
always-allow-substitutes = true
EOF

  run_apply

  [ "$status" -eq 0 ]
  [ "$(cat "$TARGET")" = "# unmanaged line
always-allow-substitutes = true

# BEGIN cons-tan-tan/dotfiles apply-nix-settings
extra-trusted-users = constantan
extra-substituters = https://cache.numtide.com
extra-trusted-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
# END cons-tan-tan/dotfiles apply-nix-settings" ]
}

@test "replaces an existing managed block only" {
  cat >"$TARGET" <<'EOF'
before = keep
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
trusted-users = root old-user
# END cons-tan-tan/dotfiles apply-nix-settings
after = keep
EOF

  run_apply

  [ "$status" -eq 0 ]
  [[ "$(cat "$TARGET")" == *"before = keep"* ]]
  [[ "$(cat "$TARGET")" == *"after = keep"* ]]
  [[ "$(cat "$TARGET")" != *"old-user"* ]]
  [[ "$(cat "$TARGET")" == *"extra-trusted-users = constantan"* ]]
}

@test "check reports drift without writing" {
  echo "before = keep" >"$TARGET"

  run_apply --check

  [ "$status" -eq 1 ]
  [[ "$output" == *"not up to date"* ]]
  [ "$(cat "$TARGET")" = "before = keep" ]
}

@test "dry-run prints diff without writing" {
  echo "before = keep" >"$TARGET"

  run_apply --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"+extra-trusted-users = constantan"* ]]
  [ "$(cat "$TARGET")" = "before = keep" ]
}

@test "malformed managed block is rejected without writing" {
  cat >"$TARGET" <<'EOF'
before = keep
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
trusted-users = root old-user
EOF

  run_apply

  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
  [[ "$(cat "$TARGET")" == *"old-user"* ]]
}

@test "reversed managed markers are rejected without writing" {
  cat >"$TARGET" <<'EOF'
before = keep
# END cons-tan-tan/dotfiles apply-nix-settings
middle = keep
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
after = keep
EOF

  run_apply

  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
  [[ "$(cat "$TARGET")" == *"middle = keep"* ]]
}

@test "include check rejects nix.conf without nix.custom.conf include" {
  local nix_conf="$WORK/nix.conf"
  echo "extra-experimental-features = nix-command flakes" >"$nix_conf"

  run_apply_with_nix_conf "$nix_conf"

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not include $TARGET"* ]]
  [ ! -e "$TARGET" ]
}

@test "include check accepts bang include for nix.custom.conf" {
  local nix_conf="$WORK/nix.conf"
  echo "!include nix.custom.conf" >"$nix_conf"

  run_apply_with_nix_conf "$nix_conf"

  [ "$status" -eq 0 ]
  [[ "$(cat "$TARGET")" == *"extra-trusted-users = constantan"* ]]
}

@test "include check rejects absolute include pointing to another nix.custom.conf" {
  local nix_conf="$WORK/nix.conf"
  mkdir -p "$WORK/other"
  echo "!include $WORK/other/nix.custom.conf" >"$nix_conf"

  run_apply_with_nix_conf "$nix_conf"

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not include $TARGET"* ]]
  [ ! -e "$TARGET" ]
}

@test "sudo re-exec preserves custom nix.conf path" {
  local nix_conf="$WORK/nix.conf"
  local sudo_log="$WORK/sudo.log"
  echo "!include nix.custom.conf" >"$nix_conf"
  : >"$sudo_log"
  chmod 666 "$sudo_log"

  mkdir -p "$STUB_DIR"
  cat >"$STUB_DIR/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SUDO_STUB_LOG"
exit 0
EOF
  chmod +x "$STUB_DIR/sudo"

  chmod 555 "$WORK"
  run env \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_NIX_CONF="$nix_conf" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    bash -eu -o pipefail "$SCRIPT"
  chmod 755 "$WORK"

  [ "$status" -eq 0 ]
  [[ "$(cat "$sudo_log")" == *"APPLY_NIX_SETTINGS_NIX_CONF=$nix_conf"* ]]
}
