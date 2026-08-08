#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  SCRIPT="$DOTFILES_TEST_REPO_ROOT/modules/features/shell/_data/nixbuild-direnvrc.sh"
  TEST_TMPDIR="$(mktemp -d)"
  GHQ_TEST_ROOT="$TEST_TMPDIR/ghq root"
  export GHQ_TEST_ROOT
  export PATH="$TEST_TMPDIR/bin:$PATH"

  mkdir -p \
    "$TEST_TMPDIR/bin" \
    "$GHQ_TEST_ROOT/github.com/cons-tan-tan/repository" \
    "$GHQ_TEST_ROOT/github.com/cons-tan-tangent/repository" \
    "$GHQ_TEST_ROOT/github.com/someone-else/repository"

  cat >"$TEST_TMPDIR/bin/ghq" <<'SH'
#!/bin/sh
printf '%s\n' "$GHQ_TEST_ROOT"
SH
  chmod +x "$TEST_TMPDIR/bin/ghq"

  source "$SCRIPT"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

apply_nixbuild_config() {
  use_nixbuild_for_ghq_owner \
    cons-tan-tan \
    x86_64-linux \
    ssh://eu.nixbuild.net \
    100 \
    1 \
    big-parallel,benchmark \
    encoded-host-key
}

@test "forces matching ghq owner repositories to use nixbuild" {
  cd "$GHQ_TEST_ROOT/github.com/cons-tan-tan/repository"
  unset NIX_CONFIG

  apply_nixbuild_config

  expected=$'builders = ssh://eu.nixbuild.net x86_64-linux - 100 1 big-parallel,benchmark - encoded-host-key\nbuilders-use-substitutes = true\nmax-jobs = 0'
  [ "$NIX_CONFIG" = "$expected" ]
  [[ $(declare -p NIX_CONFIG) == "declare -x"* ]]
}

@test "appends after existing Nix settings so the repository policy wins" {
  cd "$GHQ_TEST_ROOT/github.com/cons-tan-tan/repository"
  NIX_CONFIG='max-jobs = 4'

  apply_nixbuild_config

  [[ "$NIX_CONFIG" == $'max-jobs = 4\nbuilders = '* ]]
  [[ "$NIX_CONFIG" == *$'\nmax-jobs = 0' ]]
}

@test "leaves repositories owned by someone else unchanged" {
  cd "$GHQ_TEST_ROOT/github.com/someone-else/repository"
  unset NIX_CONFIG

  apply_nixbuild_config

  [ -z "${NIX_CONFIG+x}" ]
}

@test "does not match an owner name with a longer suffix" {
  cd "$GHQ_TEST_ROOT/github.com/cons-tan-tangent/repository"
  NIX_CONFIG='max-jobs = 2'

  apply_nixbuild_config

  [ "$NIX_CONFIG" = 'max-jobs = 2' ]
}
