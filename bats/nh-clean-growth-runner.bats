#!/usr/bin/env bats

setup() {
  load test-helper
  require_nix_fixture NH_CLEAN_GROWTH_RUNNER_BIN "nh-clean growth runner package"
  require_nix_fixture NH_CLEAN_GROWTH_TIMEOUT_RUNNER_BIN "timeout-configured nh-clean growth runner package"

  export GROWTH_CHECKER_ARGS="$BATS_TEST_TMPDIR/checker.args"
  export GROWTH_CLEANUP_ARGS="$BATS_TEST_TMPDIR/cleanup.args"
  export STATE_DIRECTORY="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STATE_DIRECTORY"
  : >"$GROWTH_CHECKER_ARGS"
}

@test "maps a no-cleanup check result to service success" {
  export GROWTH_CHECKER_STATUS=1

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" check "$STATE_DIRECTORY"

  [ "$status" -eq 0 ]
  [ ! -e "$GROWTH_CLEANUP_ARGS" ]
  mapfile -t arguments <"$GROWTH_CHECKER_ARGS"
  [ "${arguments[*]}" = "check --state-directory $STATE_DIRECTORY --store-path /test/store --growth-threshold-bytes 123 --maximum-age-seconds 789 --retry-interval-seconds 456" ]
}

@test "runs cleanup and records success when a policy limit is reached" {
  export GROWTH_CHECKER_STATUS=0

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" check "$STATE_DIRECTORY"

  [ "$status" -eq 0 ]
  mapfile -t arguments <"$GROWTH_CLEANUP_ARGS"
  [ "${arguments[*]}" = "--user start nh-clean.service" ]
  mapfile -t checker_arguments <"$GROWTH_CHECKER_ARGS"
  [ "${checker_arguments[*]}" = "check --state-directory $STATE_DIRECTORY --store-path /test/store --growth-threshold-bytes 123 --maximum-age-seconds 789 --retry-interval-seconds 456 record --state-directory $STATE_DIRECTORY --store-path /test/store" ]
}

@test "propagates cleanup failures" {
  export GROWTH_CHECKER_STATUS=0
  export GROWTH_CLEANUP_STATUS=47

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" check "$STATE_DIRECTORY"

  [ "$status" -eq 47 ]
  [ "$(wc -l <"$GROWTH_CHECKER_ARGS")" -eq 11 ]
}

@test "propagates checker failures without starting cleanup" {
  export GROWTH_CHECKER_STATUS=42

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" check "$STATE_DIRECTORY"

  [ "$status" -eq 42 ]
  [ ! -e "$GROWTH_CLEANUP_ARGS" ]
}

@test "records a baseline without starting cleanup" {
  export GROWTH_CHECKER_STATUS=0

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" record "$STATE_DIRECTORY"

  [ "$status" -eq 0 ]
  [ ! -e "$GROWTH_CLEANUP_ARGS" ]
  mapfile -t arguments <"$GROWTH_CHECKER_ARGS"
  [ "${arguments[*]}" = "record --state-directory $STATE_DIRECTORY --store-path /test/store" ]
}

@test "propagates post-cleanup record failures" {
  export GROWTH_CHECKER_STATUS=0
  export GROWTH_RECORD_STATUS=48

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" check "$STATE_DIRECTORY"

  [ "$status" -eq 48 ]
  [ -e "$GROWTH_CLEANUP_ARGS" ]
}

@test "propagates record failures without starting cleanup" {
  export GROWTH_RECORD_STATUS=42

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" record "$STATE_DIRECTORY"

  [ "$status" -eq 42 ]
  [ ! -e "$GROWTH_CLEANUP_ARGS" ]
}

@test "times out a stuck query and releases the checker lock" {
  local timeout_store=/tmp/nh-clean-growth-runner-timeout-store
  local fake_nix="$BATS_TEST_TMPDIR/nix"
  mkdir -p "$timeout_store"
  touch "$timeout_store"
  printf '%s\n' \
    '#!/bin/sh' \
    '[ -z "${FAKE_NIX_SLEEP:-}" ] || sleep "$FAKE_NIX_SLEEP"' \
    'printf '\''%s\n'\'' '\''{"/nix/store/test":{"narSize":100}}'\''' \
    >"$fake_nix"
  chmod +x "$fake_nix"
  export NIX_STORE_GROWTH_NIX="$fake_nix"
  export FAKE_NIX_SLEEP=5

  run "$NH_CLEAN_GROWTH_TIMEOUT_RUNNER_BIN" record "$STATE_DIRECTORY"
  [ "$status" -eq 124 ]

  unset FAKE_NIX_SLEEP
  run "$NH_CLEAN_GROWTH_TIMEOUT_RUNNER_BIN" record "$STATE_DIRECTORY"
  [ "$status" -eq 0 ]
  [ ! -e "$GROWTH_CLEANUP_ARGS" ]
}

@test "rejects invalid service arguments" {
  run "$NH_CLEAN_GROWTH_RUNNER_BIN" check relative
  [ "$status" -eq 2 ]
  [[ "$output" == *"STATE_DIRECTORY must be an absolute path"* ]]

  run "$NH_CLEAN_GROWTH_RUNNER_BIN" unknown "$STATE_DIRECTORY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action: unknown"* ]]
}
