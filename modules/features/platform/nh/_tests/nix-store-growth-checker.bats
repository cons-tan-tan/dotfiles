#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  export CHECKER_SOURCE="$DOTFILES_TEST_REPO_ROOT/modules/features/platform/nh/_packages/store-growth-checker/nix-store-growth-checker.sh"
  export STATE_DIRECTORY="$BATS_TEST_TMPDIR/state"
  export STORE_PATH="$BATS_TEST_TMPDIR/store"
  export FAKE_NIX_OUTPUT="$BATS_TEST_TMPDIR/nix-output.json"
  export FAKE_NIX_CALLS="$BATS_TEST_TMPDIR/nix-calls"

  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin" "$STORE_PATH"
  touch -d '@1000000000' "$STORE_PATH"
  : >"$FAKE_NIX_CALLS"

  cat >"$fake_bin/nix" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_NIX_CALLS"
if [ -n "${FAKE_NIX_EVENTS:-}" ]; then
  printf 'start %s\n' "$$" >>"$FAKE_NIX_EVENTS"
fi
if [ "${FAKE_NIX_FAIL:-false}" = true ]; then
  echo 'fake nix failure' >&2
  exit 1
fi
[ -z "${FAKE_NIX_SLEEP:-}" ] || sleep "$FAKE_NIX_SLEEP"
cat "$FAKE_NIX_OUTPUT"
if [ -n "${FAKE_NIX_EVENTS:-}" ]; then
  printf 'end %s\n' "$$" >>"$FAKE_NIX_EVENTS"
fi
EOF
  chmod +x "$fake_bin/nix"
  export NIX_STORE_GROWTH_NIX="$fake_bin/nix"
}

set_store_size() {
  printf '{"/nix/store/test":{"narSize":%s}}\n' "$1" >"$FAKE_NIX_OUTPUT"
}

change_store() {
  touch -d "@$1" "$STORE_PATH"
}

check_growth() {
  run_checker check \
    --state-directory "$STATE_DIRECTORY" \
    --store-path "$STORE_PATH" \
    --growth-threshold-bytes "${1:-50}" \
    --maximum-age-seconds 21600 \
    --retry-interval-seconds 1800
}

record_growth() {
  run_checker record \
    --state-directory "$STATE_DIRECTORY" \
    --store-path "$STORE_PATH"
}

run_checker() {
  if [[ -n ${NIX_STORE_GROWTH_CHECKER_BIN:-} ]]; then
    "$NIX_STORE_GROWTH_CHECKER_BIN" "$@"
  else
    bash "$CHECKER_SOURCE" "$@"
  fi
}

state_field() {
  cut -f"$1" "$STATE_DIRECTORY/state"
}

@test "initializes an unknown success time and requests cleanup" {
  set_store_size 100

  run check_growth

  [ "$status" -eq 0 ]
  [ "$(state_field 2)" -eq 100 ]
  [ "$(state_field 4)" -eq 0 ]
  [ "$(state_field 5)" -gt 0 ]
  [ "$(wc -l <"$FAKE_NIX_CALLS")" -eq 1 ]
  local expected_arguments="path-info --store daemon --json --all"
  if [[ -n ${NIX_STORE_GROWTH_CHECKER_BIN:-} ]]; then
    expected_arguments="path-info --store daemon --json --json-format 1 --all"
  fi
  [ "$(cat "$FAKE_NIX_CALLS")" = "$expected_arguments" ]
  [[ "$output" == *"initialized Nix store baseline: 100 bytes"* ]]
}

@test "uses directory mtime to skip the expensive Nix query" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  run check_growth

  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_NIX_CALLS")" -eq 1 ]
  [ -z "$output" ]
}

@test "requests cleanup after the maximum age without querying an unchanged store" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  local version baseline mtime trigger
  IFS=$'\t' read -r version baseline mtime _ trigger <"$STATE_DIRECTORY/state"
  printf '%s\t%s\t%s\t1\t%s\n' "$version" "$baseline" "$mtime" "$trigger" \
    >"$STATE_DIRECTORY/state"

  run check_growth

  [ "$status" -eq 0 ]
  [[ "$output" == *"cleanup maximum age reached"* ]]
  [ "$(wc -l <"$FAKE_NIX_CALLS")" -eq 1 ]
}

@test "clock rollback cannot postpone the maximum-age cleanup" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  local version baseline mtime trigger
  IFS=$'\t' read -r version baseline mtime _ trigger <"$STATE_DIRECTORY/state"
  printf '%s\t%s\t%s\t9223372036854775807\t%s\n' \
    "$version" "$baseline" "$mtime" "$trigger" >"$STATE_DIRECTORY/state"

  run check_growth

  [ "$status" -eq 0 ]
  [[ "$output" == *"cleanup maximum age reached"* ]]
  [ "$(state_field 4)" -eq 0 ]
}

@test "accumulates net growth from the last recorded baseline" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  set_store_size 120
  change_store 1000000001
  run check_growth
  [ "$status" -eq 1 ]
  [[ "$output" == *"growth below threshold: 20 bytes"* ]]
  [ "$(state_field 2)" -eq 100 ]

  set_store_size 150
  change_store 1000000002
  run check_growth

  [ "$status" -eq 0 ]
  [[ "$output" == *"growth threshold reached: 50 bytes"* ]]
  [ "$(state_field 2)" -eq 100 ]
}

@test "cools down a failed cleanup trigger and retries later" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  set_store_size 160
  change_store 1000000001
  run check_growth
  [ "$status" -eq 0 ]

  run check_growth

  [ "$status" -eq 1 ]
  [[ "$output" == *"cleanup retry is cooling down"* ]]
  [ "$(wc -l <"$FAKE_NIX_CALLS")" -eq 2 ]

  local version baseline mtime success
  IFS=$'\t' read -r version baseline mtime success _ <"$STATE_DIRECTORY/state"
  printf '%s\t%s\t%s\t%s\t1\n' "$version" "$baseline" "$mtime" "$success" \
    >"$STATE_DIRECTORY/state"

  run check_growth
  [ "$status" -eq 0 ]
}

@test "record resets the baseline after cleanup" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  set_store_size 160
  change_store 1000000001
  run check_growth
  [ "$status" -eq 0 ]

  set_store_size 70
  change_store 1000000002
  run record_growth
  [ "$status" -eq 0 ]
  [ "$(state_field 2)" -eq 70 ]
  [ "$(state_field 4)" -gt 0 ]
  [ "$(state_field 5)" -eq 0 ]

  run check_growth
  [ "$status" -eq 1 ]
}

@test "adopts a lower baseline after an external store shrink" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  set_store_size 80
  change_store 1000000001
  run check_growth

  [ "$status" -eq 1 ]
  [ "$(state_field 2)" -eq 80 ]
  [[ "$output" == *"reset Nix store baseline after shrink: 80 bytes"* ]]
}

@test "sums all registered NAR sizes including an empty store" {
  printf '{"/nix/store/first":{"narSize":40},"/nix/store/second":{"narSize":60}}\n' \
    >"$FAKE_NIX_OUTPUT"
  run record_growth
  [ "$status" -eq 0 ]
  [ "$(state_field 2)" -eq 100 ]

  printf '{}\n' >"$FAKE_NIX_OUTPUT"
  change_store 1000000001
  run check_growth
  [ "$status" -eq 1 ]
  [ "$(state_field 2)" -eq 0 ]
}

@test "does not acknowledge a failed Nix query" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  change_store 1000000001
  export FAKE_NIX_FAIL=true
  run check_growth

  [ "$status" -ne 0 ]
  [ "$(state_field 2)" -eq 100 ]

  export FAKE_NIX_FAIL=false
  set_store_size 160
  run check_growth
  [ "$status" -eq 0 ]
}

@test "recovers a corrupt state and requests immediate cleanup" {
  set_store_size 100
  run record_growth
  [ "$status" -eq 0 ]

  printf 'partial-state\n' >"$STATE_DIRECTORY/state"
  set_store_size 160
  change_store 1000000001
  run check_growth

  [ "$status" -eq 0 ]
  [ "$(state_field 2)" -eq 160 ]
  [ "$(state_field 4)" -eq 0 ]
  [ "$(state_field 5)" -gt 0 ]
  [[ "$output" == *"moved invalid Nix store growth state"* ]]
  compgen -G "$STATE_DIRECTORY/state.corrupt-*" >/dev/null

  local mtime
  mtime=$(state_field 3)
  printf '2\t9223372036854775808\t%s\t1\t0\n' "$mtime" >"$STATE_DIRECTORY/state"
  set_store_size 170
  change_store 1000000002
  run check_growth

  [ "$status" -eq 0 ]
  [ "$(state_field 2)" -eq 170 ]
}

@test "serializes concurrent state updates with a portable lock" {
  set_store_size 100
  export FAKE_NIX_EVENTS="$BATS_TEST_TMPDIR/nix-events"
  export FAKE_NIX_SLEEP=0.2
  : >"$FAKE_NIX_EVENTS"

  record_growth &
  local first=$!
  record_growth &
  local second=$!
  wait "$first"
  wait "$second"

  mapfile -t events <"$FAKE_NIX_EVENTS"
  [ "${#events[@]}" -eq 4 ]
  [[ ${events[0]} == start\ * ]]
  [[ ${events[1]} == end\ * ]]
  [[ ${events[2]} == start\ * ]]
  [[ ${events[3]} == end\ * ]]
  [ "${events[0]#start }" = "${events[1]#end }" ]
  [ "${events[2]#start }" = "${events[3]#end }" ]
}

@test "rejects unsafe or incomplete arguments" {
  run run_checker check --state-directory relative --store-path "$STORE_PATH" \
    --growth-threshold-bytes 50 --maximum-age-seconds 21600 --retry-interval-seconds 1800
  [ "$status" -eq 2 ]
  [[ "$output" == *"--state-directory must be an absolute path"* ]]

  run run_checker check --state-directory "$STATE_DIRECTORY" --store-path "$STORE_PATH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--growth-threshold-bytes must be a positive integer"* ]]

  run run_checker check --state-directory "$STATE_DIRECTORY" --store-path "$STORE_PATH" \
    --growth-threshold-bytes 08 --maximum-age-seconds 21600 --retry-interval-seconds 1800
  [ "$status" -eq 2 ]

  run run_checker check --state-directory "$STATE_DIRECTORY" --store-path "$STORE_PATH" \
    --growth-threshold-bytes 50 --maximum-age-seconds 0 --retry-interval-seconds 1800
  [ "$status" -eq 2 ]
  [[ "$output" == *"--maximum-age-seconds must be a positive integer"* ]]

  run run_checker unknown
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: unknown"* ]]
}
