#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/ghq-fetch-all/ghq-fetch-all.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  export PATH="$TEST_TMPDIR/bin:$PATH"
  mkdir -p "$TEST_TMPDIR/bin"

  cat >"$TEST_TMPDIR/bin/ghq" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '/tmp/repo one' '/tmp/repo-two'
SH
  cat >"$TEST_TMPDIR/bin/timeout" <<'SH'
#!/usr/bin/env bash
printf 'timeout:%s\n' "$*" >>"$TEST_TMPDIR/log"
shift
exec "$@"
SH
  cat >"$TEST_TMPDIR/bin/git" <<'SH'
#!/usr/bin/env bash
printf 'git:%s\n' "$*" >>"$TEST_TMPDIR/log"
if [ "$2" = "/tmp/repo one" ]; then
  exit 1
fi
SH
  chmod +x "$TEST_TMPDIR/bin/ghq" "$TEST_TMPDIR/bin/timeout" "$TEST_TMPDIR/bin/git"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "fetches each repository with bounded parallelism and timeout" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: fetch failed for /tmp/repo one"* ]]
  grep -F "timeout:60s git -C /tmp/repo one fetch --all --prune --quiet" "$TEST_TMPDIR/log"
  grep -F "timeout:60s git -C /tmp/repo-two fetch --all --prune --quiet" "$TEST_TMPDIR/log"
}
