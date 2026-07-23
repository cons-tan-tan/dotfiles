#!/usr/bin/env bats
# apply-nix-settings の managed block 更新を、/etc ではなく一時ファイルで検査する。

setup() {
  BASH_BIN="$(command -v bash)"
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

  if [ -z "${APPLY_NIX_SETTINGS_TEST_BIN:-}" ]; then
    echo "APPLY_NIX_SETTINGS_TEST_BIN must identify the unwrapped apply-nix-settings binary" >&2
    return 1
  fi
  case "$APPLY_NIX_SETTINGS_TEST_BIN" in
  /*) ;;
  *)
    echo "APPLY_NIX_SETTINGS_TEST_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  if [ ! -x "$APPLY_NIX_SETTINGS_TEST_BIN" ]; then
    echo "APPLY_NIX_SETTINGS_TEST_BIN is not executable: $APPLY_NIX_SETTINGS_TEST_BIN" >&2
    return 1
  fi
}

teardown() {
  rm -rf "$WORK"
}

run_apply() {
  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" "$@"
}

run_apply_with_nix_conf() {
  local nix_conf=$1
  shift
  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_NIX_CONF="$nix_conf" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" "$@"
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
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

@test "a second run is idempotent" {
  run_apply
  [ "$status" -eq 0 ]
  local first_content
  first_content="$(cat "$TARGET")"

  run_apply

  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
  [ "$(cat "$TARGET")" = "$first_content" ]
}

@test "adds the managed block to an empty file" {
  : >"$TARGET"

  run_apply

  [ "$status" -eq 0 ]
  [ "$(cat "$TARGET")" = "# BEGIN cons-tan-tan/dotfiles apply-nix-settings
extra-trusted-users = constantan
extra-substituters = https://cache.numtide.com
extra-trusted-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
# END cons-tan-tan/dotfiles apply-nix-settings" ]
}

@test "adds one blank line after content with a trailing newline" {
  printf 'before = keep\n' >"$TARGET"

  run_apply

  [ "$status" -eq 0 ]
  [[ "$(cat "$TARGET")" == $'before = keep\n\n# BEGIN'* ]]
}

@test "terminates content without a trailing newline before the block" {
  printf 'before = keep' >"$TARGET"

  run_apply

  [ "$status" -eq 0 ]
  [[ "$(cat "$TARGET")" == $'before = keep\n# BEGIN'* ]]
}

@test "snippet without trailing newline preserves the current marker boundary" {
  printf 'extra-trusted-users = constantan' >"$SNIPPET"

  run_apply

  [ "$status" -eq 0 ]
  [[ "$(cat "$TARGET")" == *"extra-trusted-users = constantan# END cons-tan-tan/dotfiles apply-nix-settings" ]]
}

@test "check reports drift without writing" {
  echo "before = keep" >"$TARGET"

  run_apply --check

  [ "$status" -eq 1 ]
  [[ "$output" == *"not up to date"* ]]
  [ "$(cat "$TARGET")" = "before = keep" ]
  [ ! -e "$WORK/.apply-nix-settings.lock" ]
}

@test "dry-run prints diff without writing" {
  echo "before = keep" >"$TARGET"

  run_apply --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"+extra-trusted-users = constantan"* ]]
  [ "$(cat "$TARGET")" = "before = keep" ]
  [ ! -e "$WORK/.apply-nix-settings.lock" ]
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

@test "multiple managed blocks are rejected without writing" {
  cat >"$TARGET" <<'EOF'
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
first = keep
# END cons-tan-tan/dotfiles apply-nix-settings
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
second = keep
# END cons-tan-tan/dotfiles apply-nix-settings
EOF

  run_apply

  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
  [[ "$(cat "$TARGET")" == *"second = keep"* ]]
}

@test "duplicate begin marker is rejected without writing" {
  cat >"$TARGET" <<'EOF'
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
# END cons-tan-tan/dotfiles apply-nix-settings
EOF

  run_apply

  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
}

@test "duplicate end marker is rejected without writing" {
  cat >"$TARGET" <<'EOF'
# BEGIN cons-tan-tan/dotfiles apply-nix-settings
# END cons-tan-tan/dotfiles apply-nix-settings
# END cons-tan-tan/dotfiles apply-nix-settings
EOF

  run_apply

  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed managed block"* ]]
}

@test "lines containing only part of a marker are preserved" {
  cat >"$TARGET" <<'EOF'
note = prefix # BEGIN cons-tan-tan/dotfiles apply-nix-settings suffix
EOF

  run_apply

  [ "$status" -eq 0 ]
  [[ "$(cat "$TARGET")" == *"note = prefix # BEGIN cons-tan-tan/dotfiles apply-nix-settings suffix"* ]]
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

@test "include check accepts the absolute target path" {
  local nix_conf="$WORK/nix.conf"
  echo "include $TARGET" >"$nix_conf"

  run_apply_with_nix_conf "$nix_conf"

  [ "$status" -eq 0 ]
}

@test "bare relative target and nix.conf paths use the current directory" {
  printf '!include nix.custom.conf\n' >"$WORK/nix.conf"

  run env \
    APPLY_NIX_SETTINGS_CONF="nix.custom.conf" \
    APPLY_NIX_SETTINGS_NIX_CONF="nix.conf" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    "$BASH_BIN" -c 'cd "$1" && exec "$2"' _ "$WORK" "$APPLY_NIX_SETTINGS_TEST_BIN"

  [ "$status" -eq 0 ]
  [ -f "$WORK/nix.custom.conf" ]
  [[ "$(cat "$WORK/nix.custom.conf")" == *"extra-trusted-users = constantan"* ]]
}

@test "nested relative target creates missing directories from the current directory" {
  run env \
    APPLY_NIX_SETTINGS_CONF="missing/nix.custom.conf" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    "$BASH_BIN" -c 'cd "$1" && exec "$2"' _ "$WORK" "$APPLY_NIX_SETTINGS_TEST_BIN"

  [ "$status" -eq 0 ]
  [ -f "$WORK/missing/nix.custom.conf" ]
  [ "$(file_mode "$WORK/missing")" = "755" ]
}

@test "include check compares symlinked ancestor paths physically" {
  local real_dir="$WORK/real"
  local link_dir="$WORK/link"
  local nix_conf="$WORK/nix.conf"
  mkdir -p "$real_dir"
  ln -s "$real_dir" "$link_dir"
  TARGET="$link_dir/nix.custom.conf"
  echo "!include $real_dir/nix.custom.conf" >"$nix_conf"

  run_apply_with_nix_conf "$nix_conf"

  [ "$status" -eq 0 ]
  [ -f "$real_dir/nix.custom.conf" ]
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
  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/sudo"
  cat >>"$STUB_DIR/sudo" <<'EOF'
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
    "$APPLY_NIX_SETTINGS_TEST_BIN"
  chmod 755 "$WORK"

  [ "$status" -eq 0 ]
  [[ "$(cat "$sudo_log")" == *"APPLY_NIX_SETTINGS_NIX_CONF=$nix_conf"* ]]
  [[ "$(cat "$sudo_log")" == *"APPLY_NIX_SETTINGS_SNIPPET=$SNIPPET"* ]]
  [[ "$(cat "$sudo_log")" == *"APPLY_NIX_SETTINGS_SUDO=$STUB_DIR/sudo"* ]]
  [[ "$(cat "$sudo_log")" == *"$APPLY_NIX_SETTINGS_TEST_BIN"* ]]
}

@test "sudo child nonzero status is propagated" {
  local sudo_log="$WORK/sudo.log"
  : >"$sudo_log"
  chmod 666 "$sudo_log"
  mkdir -p "$STUB_DIR"
  printf '#!%s\nexit 73\n' "$BASH_BIN" >"$STUB_DIR/sudo"
  chmod +x "$STUB_DIR/sudo"

  chmod 555 "$WORK"
  run env \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN"
  chmod 755 "$WORK"

  [ "$status" -eq 73 ]
}

@test "check takes precedence over dry-run" {
  echo "before = keep" >"$TARGET"

  run_apply --check --dry-run

  [ "$status" -eq 1 ]
  [[ "$output" == *"not up to date"* ]]
  [ "$(cat "$TARGET")" = "before = keep" ]
}

@test "help succeeds and unknown options are usage errors" {
  run_apply --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: apply-nix-settings"* ]]

  run_apply --unknown
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "new and replaced targets have mode 0644" {
  run_apply
  [ "$status" -eq 0 ]
  [ "$(file_mode "$TARGET")" = "644" ]

  chmod 600 "$TARGET"
  printf 'extra-trusted-users = changed\n' >"$SNIPPET"
  run_apply
  [ "$status" -eq 0 ]
  [ "$(file_mode "$TARGET")" = "644" ]
}

@test "new target directory has mode 0755" {
  local target_dir="$WORK/new/nix"
  TARGET="$target_dir/nix.custom.conf"

  run_apply

  [ "$status" -eq 0 ]
  [ "$(file_mode "$target_dir")" = "755" ]
  [ "$(file_mode "$TARGET")" = "644" ]
}

@test "snippet must be a regular file" {
  rm "$SNIPPET"
  mkdir "$SNIPPET"

  run_apply

  [ "$status" -eq 1 ]
  [[ "$output" == *"snippet is not a regular file"* ]]
  [ ! -e "$TARGET" ]
}

@test "target symlink is rejected without changing its referent" {
  local real="$WORK/real.conf"
  printf 'keep = true\n' >"$real"
  ln -s "$real" "$TARGET"

  run_apply

  [ "$status" -eq 1 ]
  [[ "$output" == *"must not be a symlink"* ]]
  [ "$(cat "$real")" = "keep = true" ]
}

@test "directory and FIFO targets are rejected" {
  mkdir "$TARGET"
  run_apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a regular file"* ]]
  rmdir "$TARGET"

  mkfifo "$TARGET"
  run_apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a regular file"* ]]
  [ -p "$TARGET" ]
}

@test "check and dry-run independently create no directory lock temp file or sudo process" {
  local target_dir="$WORK/missing"
  local sudo_log="$WORK/sudo-called"
  TARGET="$target_dir/nix.custom.conf"
  mkdir -p "$STUB_DIR"
  printf '#!%s\nprintf called >\"$SUDO_STUB_LOG\"\n' "$BASH_BIN" >"$STUB_DIR/sudo"
  chmod +x "$STUB_DIR/sudo"

  run env \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" --check

  [ "$status" -eq 1 ]
  [ ! -e "$target_dir" ]
  [ ! -e "$sudo_log" ]

  run env \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" --dry-run

  [ "$status" -eq 0 ]
  [ ! -e "$target_dir" ]
  [ ! -e "$sudo_log" ]
}

@test "sudo handoff leaves no pre-elevation temporary artifacts" {
  local locked_dir="$WORK/locked"
  local sudo_log="$WORK/sudo.log"
  local temp_dir="$WORK/tmp"
  mkdir -p "$locked_dir" "$temp_dir" "$STUB_DIR"
  TARGET="$locked_dir/nix.custom.conf"
  : >"$sudo_log"
  chmod 666 "$sudo_log"
  printf '#!%s\nprintf \"%%s\\n\" \"$@\" >\"$SUDO_STUB_LOG\"\n' "$BASH_BIN" >"$STUB_DIR/sudo"
  chmod +x "$STUB_DIR/sudo"
  chmod 555 "$locked_dir"

  run env \
    TMPDIR="$temp_dir" \
    SUDO_STUB_LOG="$sudo_log" \
    APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$SNIPPET" \
    APPLY_NIX_SETTINGS_SUDO="$STUB_DIR/sudo" \
    "$APPLY_NIX_SETTINGS_TEST_BIN"
  chmod 755 "$locked_dir"

  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$temp_dir")" ]
  [ ! -e "$locked_dir/.apply-nix-settings.lock" ]
}

@test "concurrent writers leave one complete managed block" {
  local snippet_one="$WORK/snippet-one.conf"
  local snippet_two="$WORK/snippet-two.conf"
  local log_one="$WORK/one.log"
  local log_two="$WORK/two.log"
  printf 'writer = one\n' >"$snippet_one"
  printf 'writer = two\n' >"$snippet_two"
  printf 'before = keep\n' >"$TARGET"

  env APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$snippet_one" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" >"$log_one" 2>&1 &
  local pid_one=$!
  env APPLY_NIX_SETTINGS_CONF="$TARGET" \
    APPLY_NIX_SETTINGS_SNIPPET="$snippet_two" \
    "$APPLY_NIX_SETTINGS_TEST_BIN" >"$log_two" 2>&1 &
  local pid_two=$!

  wait "$pid_one"
  local status_one=$?
  wait "$pid_two"
  local status_two=$?

  [ "$status_one" -eq 0 ]
  [ "$status_two" -eq 0 ]
  [ "$(grep -c '^# BEGIN cons-tan-tan/dotfiles apply-nix-settings$' "$TARGET")" -eq 1 ]
  [ "$(grep -c '^# END cons-tan-tan/dotfiles apply-nix-settings$' "$TARGET")" -eq 1 ]
  [[ "$(cat "$TARGET")" == *"before = keep"* ]]
  [[ "$(cat "$TARGET")" == *"writer = one"* || "$(cat "$TARGET")" == *"writer = two"* ]]
}
