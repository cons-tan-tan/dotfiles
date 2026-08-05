#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  SCRIPT="$REPO_ROOT/modules/features/agents/herdr/_packages/herdr/herdr-wrapper.sh"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  TRACE_FILE="$WORK/trace"
  ARGS_FILE="$WORK/args"
  STUB_DIR="$WORK/stub"
  HERDR_STUB="$STUB_DIR/herdr"
  SLEEP_STUB="$STUB_DIR/sleep"

  mkdir -p "$STUB_DIR"
  printf '#!%s\n' "$BASH_BIN" > "$HERDR_STUB"
  cat >> "$HERDR_STUB" <<'EOS'
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
} >"$HERDR_STUB_ARGS"
EOS
  chmod +x "$HERDR_STUB"

  printf '#!%s\nexit 0\n' "$BASH_BIN" >"$SLEEP_STUB"
  chmod +x "$SLEEP_STUB"
}

teardown() {
  rm -rf "$WORK"
}

run_wrapper() {
  local -a command=(
    env -i
    "PATH=$PATH"
    "HOME=$HOME"
    "HERDR_BIN=$HERDR_STUB"
    "HERDR_SLEEP_BIN=$SLEEP_STUB"
    "HERDR_STUB_ARGS=$ARGS_FILE"
    "HERDR_WRAPPER_TRACE=$TRACE_FILE"
  )

  if [ "${RUN_WITH_WT_SESSION:-1}" = "1" ]; then
    command+=("WT_SESSION=x")
  fi
  if [ "${RUN_WITH_WSL_DISTRO_NAME:-1}" = "1" ]; then
    command+=("WSL_DISTRO_NAME=y")
  fi
  if [ "${RUN_WITH_ASSUME_TTY:-1}" = "1" ]; then
    command+=("HERDR_WRAPPER_ASSUME_TTY=1")
  fi

  run "${command[@]}" bash -eu -o pipefail "$SCRIPT" "$@"
}

assert_trace() {
  [ "$(cat "$TRACE_FILE")" = "workaround" ]
}

assert_no_trace() {
  [ ! -e "$TRACE_FILE" ] || [ ! -s "$TRACE_FILE" ]
}

assert_stub_args() {
  local expected=$1

  [ "$(cat "$ARGS_FILE")" = "$expected" ]
}

@test "no arguments enables workaround and execs herdr without arguments" {
  run_wrapper

  [ "$status" -eq 0 ]
  assert_trace
  assert_stub_args "argc=0"
}

@test "--session enables workaround" {
  run_wrapper --session foo

  [ "$status" -eq 0 ]
  assert_trace
}

@test "session attach enables workaround" {
  run_wrapper session attach

  [ "$status" -eq 0 ]
  assert_trace
}

@test "session list does not enable workaround" {
  run_wrapper session list

  [ "$status" -eq 0 ]
  assert_no_trace
}

@test "unmatched command does not enable workaround" {
  run_wrapper run

  [ "$status" -eq 0 ]
  assert_no_trace
}

@test "missing WT_SESSION disables workaround" {
  RUN_WITH_WT_SESSION=0 run_wrapper

  [ "$status" -eq 0 ]
  assert_no_trace
}

@test "missing WSL_DISTRO_NAME disables workaround" {
  RUN_WITH_WSL_DISTRO_NAME=0 run_wrapper

  [ "$status" -eq 0 ]
  assert_no_trace
}

@test "non-tty stdout disables workaround" {
  RUN_WITH_ASSUME_TTY=0 run_wrapper

  [ "$status" -eq 0 ]
  assert_no_trace
}

@test "arguments are forwarded to herdr" {
  run_wrapper session attach --flag

  [ "$status" -eq 0 ]
  assert_stub_args $'argc=3\narg=session\narg=attach\narg=--flag'
}

@test "Nix package pins both the Herdr child and sleep dependency" {
  if [[ -z ${HERDR_WRAPPER_TEST_PACKAGE:-} ]]; then
    skip "HERDR_WRAPPER_TEST_PACKAGE is only available in the Nix check"
  fi

  run env TEST_TMPDIR="$WORK" \
    "$HERDR_WRAPPER_TEST_PACKAGE/bin/herdr" package-arg

  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/package-args")" = "package-arg" ]
  grep -E 'HERDR_SLEEP_BIN=/nix/store/.+-herdr-sleep-fixture/bin/herdr-sleep-fixture' \
    "$(readlink -f "$HERDR_WRAPPER_TEST_PACKAGE/bin/herdr")"
}
