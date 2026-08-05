#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  SCRIPT="$REPO_ROOT/modules/features/source-control/ghq-sync/_packages/fetch-all/ghq-fetch-all.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  export PATH="$TEST_TMPDIR/bin:$PATH"
  export GHQ_REPOSITORIES_FILE="$TEST_TMPDIR/repositories"
  mkdir -p "$TEST_TMPDIR/bin" "$TEST_TMPDIR/timeout-args" "$TEST_TMPDIR/git-args"

  write_bash_stub "$TEST_TMPDIR/bin/ghq" <<'SH'
cat "$GHQ_REPOSITORIES_FILE"
SH
  write_bash_stub "$TEST_TMPDIR/bin/timeout" <<'SH'
printf '%s\0' "$@" >"$TEST_TMPDIR/timeout-args/$BASHPID"
shift
exec "$@"
SH
  write_bash_stub "$TEST_TMPDIR/bin/git" <<'SH'
printf '%s\0' "$@" >"$TEST_TMPDIR/git-args/$BASHPID"
if [ "$2" = "${FAIL_REPOSITORY:-}" ]; then
  exit 1
fi
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

assert_nul_argv_call() {
  local directory=$1
  shift
  local -a expected=("$@")
  local call_file

  for call_file in "$directory"/*; do
    [ -e "$call_file" ] || continue
    local -a actual=()
    mapfile -d '' -t actual <"$call_file"
    if [ "${#actual[@]}" -ne "${#expected[@]}" ]; then
      continue
    fi

    local matches=true
    local index
    for ((index = 0; index < ${#expected[@]}; index++)); do
      if [ "${actual[$index]}" != "${expected[$index]}" ]; then
        matches=false
        break
      fi
    done
    if [ "$matches" = true ]; then
      return 0
    fi
  done

  return 1
}

@test "preserves repository paths through xargs and bounds each fetch with timeout" {
  local repository_one="/tmp/repo one"
  local repository_two="/tmp/repo's \"quoted\"\\path"
  local repository_three="  /tmp/leading whitespace"
  printf '%s\n' "$repository_one" "$repository_two" "$repository_three" >"$GHQ_REPOSITORIES_FILE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  assert_nul_argv_call "$TEST_TMPDIR/timeout-args" \
    60s git -C "$repository_one" fetch --all --prune --quiet
  assert_nul_argv_call "$TEST_TMPDIR/timeout-args" \
    60s git -C "$repository_two" fetch --all --prune --quiet
  assert_nul_argv_call "$TEST_TMPDIR/timeout-args" \
    60s git -C "$repository_three" fetch --all --prune --quiet
  assert_nul_argv_call "$TEST_TMPDIR/git-args" \
    -C "$repository_two" fetch --all --prune --quiet
}

@test "does not start a child process for an empty repository list" {
  : >"$GHQ_REPOSITORIES_FILE"

  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ -z "$(find "$TEST_TMPDIR/timeout-args" -type f -print -quit)" ]
  [ -z "$(find "$TEST_TMPDIR/git-args" -type f -print -quit)" ]
}

@test "warns on one failure, continues fetching, and exits successfully" {
  local failed_repository="/tmp/failing repo"
  local successful_repository="/tmp/still fetched"
  printf '%s\n' "$failed_repository" "$successful_repository" >"$GHQ_REPOSITORIES_FILE"

  run env FAIL_REPOSITORY="$failed_repository" bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: fetch failed for $failed_repository"* ]]
  assert_nul_argv_call "$TEST_TMPDIR/git-args" \
    -C "$failed_repository" fetch --all --prune --quiet
  assert_nul_argv_call "$TEST_TMPDIR/git-args" \
    -C "$successful_repository" fetch --all --prune --quiet
}
