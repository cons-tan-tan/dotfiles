#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture NIX_MUTATION_TEST_BIN "Nix mutation test runner"
  TEST_ROOT=$BATS_TEST_TMPDIR/repo
  mkdir -p "$TEST_ROOT"
}

write_target() {
  printf '%s\n' "$1" >"$TEST_ROOT/target.nix"
}

run_mutation_test() {
  run "$NIX_MUTATION_TEST_BIN" --root "$TEST_ROOT" "$@" target.nix
}

@test "help exposes the command contract" {
  run "$NIX_MUTATION_TEST_BIN" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Test command environment:"* ]]
  [[ "$output" == *"Source annotations:"* ]]
  [[ "$output" == *"Exit status:"* ]]
  [[ "$output" == *"0  Every executed valid mutant was killed, --list completed, or help was shown"* ]]
  [[ "$output" == *"2  Invalid arguments or input, a failing or timed-out baseline, or a runner error"* ]]
}

@test "candidate listing uses the lossless Nix syntax tree" {
  write_target '{ value = true; text = "true"; # true
  }'

  run_mutation_test --list --operator boolean

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -s 'length')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.mutation')" = boolean-true ]
  [ "$(printf '%s\n' "$output" | jq -r '.operator')" = boolean ]
  [ "$(printf '%s\n' "$output" | jq -r '.replacement')" = false ]
  [[ "$(printf '%s\n' "$output" | jq -r '.id')" =~ ^[0-9a-f]{16}$ ]]
  [[ "$(printf '%s\n' "$output" | jq -r '.sourceHash')" =~ ^[0-9a-f]{64}$ ]]
}

@test "an inline marker suppresses a known equivalent mutant" {
  write_target '{ ignored = true; # nix-mutation-test: ignore
    observed = false;
  }'

  run_mutation_test --list --operator boolean

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -s 'length')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.mutation')" = boolean-false ]
}

@test "a behavioral assertion kills a boolean mutant without changing the source" {
  write_target true

  run_mutation_test \
    --operator boolean \
    --test-command '[[ ( $NIX_MUTATION_ID == baseline && $NIX_MUTATION_KIND == baseline && -z $NIX_MUTATION_TARGET ) || ( $NIX_MUTATION_ID =~ ^[0-9a-f]{16}$ && $NIX_MUTATION_KIND == boolean-true && $NIX_MUTATION_TARGET == target.nix ) ]] && [[ $(nix-instantiate --store dummy:// --eval --strict --json target.nix) == true ]]'

  [ "$status" -eq 0 ]
  [[ "$output" == *"MUTANT 1/1 killed boolean-true target.nix:1:1"* ]]
  [[ "$output" == *"SUMMARY total=1 killed=1 survived=0 invalid=0 timeout=0"* ]]
  [ "$(<"$TEST_ROOT/target.nix")" = true ]
}

@test "a parse-only assertion reports a surviving mutant" {
  write_target true

  run_mutation_test \
    --operator boolean \
    --test-command 'nix-instantiate --store dummy:// --parse target.nix >/dev/null'

  [ "$status" -eq 1 ]
  [[ "$output" == *"MUTANT 1/1 survived boolean-true target.nix:1:1"* ]]
  [[ "$output" == *"SUMMARY total=1 killed=0 survived=1 invalid=0 timeout=0"* ]]
}

@test "logical and equality operators are listed independently" {
  write_target '(true && false) == false'

  run_mutation_test --list --operator logical
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -s 'length')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.mutation')" = logical-and ]

  run_mutation_test --list --operator equality
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -s 'length')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.mutation')" = equality-equal ]
}

@test "logical mutation replaces only the operator token" {
  write_target '(true  &&
    false)'

  run_mutation_test \
    --operator logical \
    --test-command '[[ $NIX_MUTATION_ID == baseline || ( $(sed -n 1p target.nix) == "(true  ||" && $(sed -n 2p target.nix) == "    false)" ) ]]'

  [ "$status" -eq 1 ]
  [[ "$output" == *"MUTANT 1/1 survived logical-and target.nix:1:8 \"&&\" -> \"||\""* ]]
}

@test "a failing baseline aborts before executing mutants" {
  write_target true

  run_mutation_test --test-command false

  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline test failed with status 1"* ]]
  [[ "$output" != *"MUTANT"* ]]
}

@test "a timed out mutant is reported separately" {
  write_target true

  run_mutation_test \
    --operator boolean \
    --timeout 1 \
    --test-command '[[ $NIX_MUTATION_ID == baseline ]] || sleep 2'

  [ "$status" -eq 1 ]
  [[ "$output" == *"MUTANT 1/1 timeout boolean-true target.nix:1:1"* ]]
  [[ "$output" == *"SUMMARY total=1 killed=0 survived=0 invalid=0 timeout=1"* ]]
}

@test "a timed out process that ignores TERM is killed" {
  write_target true

  run timeout --kill-after=1 5 \
    "$NIX_MUTATION_TEST_BIN" \
    --root "$TEST_ROOT" \
    --operator boolean \
    --timeout 1 \
    --test-command '[[ $NIX_MUTATION_ID == baseline ]] || { trap "" TERM; while :; do :; done; }' \
    target.nix

  [ "$status" -eq 1 ]
  [[ "$output" == *"MUTANT 1/1 timeout boolean-true target.nix:1:1"* ]]
}

@test "a command exit status 124 is a killed mutant, not a timeout" {
  write_target true

  run_mutation_test \
    --operator boolean \
    --timeout 2 \
    --test-command '[[ $NIX_MUTATION_ID == baseline ]] || exit 124'

  [ "$status" -eq 0 ]
  [[ "$output" == *"MUTANT 1/1 killed boolean-true target.nix:1:1"* ]]
  [[ "$output" == *"SUMMARY total=1 killed=1 survived=0 invalid=0 timeout=0"* ]]
}

@test "duplicate target spellings run each mutant once" {
  write_target true

  run "$NIX_MUTATION_TEST_BIN" \
    --root "$TEST_ROOT" \
    --list \
    target.nix \
    ./target.nix

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -s 'length')" -eq 1 ]
}

@test "an unrepresentable timeout is rejected without panicking" {
  write_target true
  local marker=$BATS_TEST_TMPDIR/command-started

  run_mutation_test \
    --timeout 18446744073709551615 \
    --test-command "touch '$marker'; while :; do :; done"

  [ "$status" -eq 2 ]
  [[ "$output" == *"test command timeout is too large"* ]]
  [[ "$output" != *"panicked"* ]]
  [ ! -e "$marker" ]
}

@test "background descendants are cleaned after a command exits" {
  write_target true
  local pid_file=$BATS_TEST_TMPDIR/background-pid

  run_mutation_test \
    --operator boolean \
    --test-command "[[ \$NIX_MUTATION_ID == baseline ]] || { sleep 30 & echo \$! > '$pid_file'; }"

  [ "$status" -eq 1 ]
  local background_pid
  background_pid=$(<"$pid_file")
  if kill -0 "$background_pid" 2>/dev/null; then
    kill -KILL "$background_pid" 2>/dev/null || true
    false
  fi
}

@test "large command output is discarded without changing its status" {
  write_target true

  run_mutation_test \
    --operator boolean \
    --test-command 'yes output | head -c 2097152'

  [ "$status" -eq 1 ]
  [[ "$output" == *"MUTANT 1/1 survived boolean-true target.nix:1:1"* ]]
}

@test "targets outside the declared root are rejected" {
  printf 'true\n' >"$BATS_TEST_TMPDIR/outside.nix"

  run "$NIX_MUTATION_TEST_BIN" \
    --root "$TEST_ROOT" \
    --list \
    "$BATS_TEST_TMPDIR/outside.nix"

  [ "$status" -eq 2 ]
  [[ "$output" == *"target is outside root"* ]]
}
