#!/usr/bin/env bats

setup() {
  if [[ -z ${NH_RESULT_ROOT_PRUNER_BIN:-} ]]; then
    skip "NH_RESULT_ROOT_PRUNER_BIN is only available in the Nix-backed Bats check"
  fi
  PRUNER=$NH_RESULT_ROOT_PRUNER_BIN
  export NH_GCROOTS_DIR="$BATS_TEST_TMPDIR/gcroots"
  mkdir -p "$NH_GCROOTS_DIR" "$BATS_TEST_TMPDIR/project/.direnv"
}

make_result_root() {
  local name=$1
  local age=$2
  local result="$BATS_TEST_TMPDIR/project/$name"

  ln -s /nix/store/test-output "$result"
  touch -h -d "$age" "$result"
  ln -s "$result" "$NH_GCROOTS_DIR/$name"
}

@test "removes stale result and result-* symlinks" {
  make_result_root result "8 days ago"
  make_result_root result-dev "8 days ago"

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ ! -L "$BATS_TEST_TMPDIR/project/result" ]
  [ ! -L "$BATS_TEST_TMPDIR/project/result-dev" ]
  [ -L "$NH_GCROOTS_DIR/result" ]
  [ -L "$NH_GCROOTS_DIR/result-dev" ]
}

@test "keeps recent result symlinks" {
  make_result_root result "1 day ago"

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ -L "$BATS_TEST_TMPDIR/project/result" ]
}

@test "dry-run reports but keeps stale result symlinks" {
  make_result_root result "8 days ago"

  run "$PRUNER" --keep-minutes 10080 --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove $BATS_TEST_TMPDIR/project/result"* ]]
  [ -L "$BATS_TEST_TMPDIR/project/result" ]
}

@test "ignores direnv and non-result roots" {
  local direnv_root="$BATS_TEST_TMPDIR/project/.direnv/flake-profile"
  local direnv_result="$BATS_TEST_TMPDIR/project/.direnv/result"
  local layout_result="$BATS_TEST_TMPDIR/project/direnv/layouts/dev/result-dev"
  local current_home="$BATS_TEST_TMPDIR/project/current-home"

  mkdir -p "$(dirname "$layout_result")"
  ln -s /nix/store/test-direnv "$direnv_root"
  ln -s /nix/store/test-direnv-result "$direnv_result"
  ln -s /nix/store/test-layout-result "$layout_result"
  ln -s /nix/store/test-home "$current_home"
  touch -h -d "30 days ago" "$direnv_root" "$direnv_result" "$layout_result" "$current_home"
  ln -s "$direnv_root" "$NH_GCROOTS_DIR/direnv"
  ln -s "$direnv_result" "$NH_GCROOTS_DIR/direnv-result"
  ln -s "$layout_result" "$NH_GCROOTS_DIR/layout-result"
  ln -s "$current_home" "$NH_GCROOTS_DIR/current-home"

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ -L "$direnv_root" ]
  [ -L "$direnv_result" ]
  [ -L "$layout_result" ]
  [ -L "$current_home" ]
}

@test "ignores result links that do not point directly into the Nix store" {
  local arbitrary="$BATS_TEST_TMPDIR/project/result"
  local nested="$BATS_TEST_TMPDIR/project/result-dev"

  ln -s /tmp/not-a-store-path "$arbitrary"
  ln -s /nix/store/test-output/bin/tool "$nested"
  touch -h -d "30 days ago" "$arbitrary" "$nested"
  ln -s "$arbitrary" "$NH_GCROOTS_DIR/arbitrary"
  ln -s "$nested" "$NH_GCROOTS_DIR/nested"

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ -L "$arbitrary" ]
  [ -L "$nested" ]
}

@test "skips dangling registrations and remains idempotent" {
  local dangling="$BATS_TEST_TMPDIR/project/result"

  ln -s "$dangling" "$NH_GCROOTS_DIR/first-dangling"
  make_result_root result-dev "8 days ago"

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ ! -L "$BATS_TEST_TMPDIR/project/result-dev" ]

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
}

@test "ignores relative registry destinations" {
  make_result_root result "8 days ago"
  rm "$NH_GCROOTS_DIR/result"
  ln -s ../project/result "$NH_GCROOTS_DIR/result"

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ -L "$BATS_TEST_TMPDIR/project/result" ]
}

@test "keeps result links not owned by the effective user" {
  make_result_root result "8 days ago"
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"

  mkdir -p "$fake_bin"
  printf '#!/bin/sh\nprintf "99999\\n"\n' >"$fake_bin/id"
  chmod +x "$fake_bin/id"

  run env NH_ID_BIN="$fake_bin/id" "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ -L "$BATS_TEST_TMPDIR/project/result" ]
}

@test "keeps a result link replaced during cleanup" {
  make_result_root result "8 days ago"
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  export REAL_STAT
  export RACE_COUNTER="$BATS_TEST_TMPDIR/stat-count"
  export RACE_TARGET="$BATS_TEST_TMPDIR/project/result"
  REAL_STAT=$(command -v stat)

  mkdir -p "$fake_bin"
  printf '0\n' >"$RACE_COUNTER"
  printf '%s\n' \
    '#!/bin/sh' \
    'count=$(cat "$RACE_COUNTER")' \
    'if [ "$count" -eq 1 ]; then' \
    '  rm "$RACE_TARGET"' \
    '  ln -s /nix/store/new-output "$RACE_TARGET"' \
    'fi' \
    'printf "%s\n" "$((count + 1))" >"$RACE_COUNTER"' \
    'exec "$REAL_STAT" "$@"' \
    >"$fake_bin/stat"
  chmod +x "$fake_bin/stat"

  run env NH_STAT_BIN="$fake_bin/stat" "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped changed result link: $RACE_TARGET"* ]]
  [ "$(readlink "$RACE_TARGET")" = "/nix/store/new-output" ]
}

@test "never deletes a regular file named result" {
  local result="$BATS_TEST_TMPDIR/project/result"

  printf 'keep me\n' >"$result"
  touch -d "30 days ago" "$result"
  ln -s "$result" "$NH_GCROOTS_DIR/result"

  run "$PRUNER" --keep-minutes 10080

  [ "$status" -eq 0 ]
  [ -f "$result" ]
  [ "$(cat "$result")" = "keep me" ]
}

@test "rejects invalid retention values" {
  run "$PRUNER" --keep-minutes 0

  [ "$status" -eq 2 ]
  [[ "$output" == *"--keep-minutes must be a positive integer"* ]]
}

@test "rejects a missing retention value and unknown arguments" {
  run "$PRUNER" --keep-minutes

  [ "$status" -eq 2 ]
  [[ "$output" == *"--keep-minutes requires a value"* ]]

  run "$PRUNER" --unknown

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument: --unknown"* ]]
}

@test "succeeds when the gcroot registry is absent" {
  run env NH_GCROOTS_DIR="$BATS_TEST_TMPDIR/missing" "$PRUNER"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
