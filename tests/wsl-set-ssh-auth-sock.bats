#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/test-helper.bash"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/wsl-set-ssh-auth-sock/set-ssh-auth-sock.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  write_bash_stub "$TEST_TMPDIR/gpgconf" <<'SH'
echo called >>"$TEST_TMPDIR/gpgconf.log"
printf '%s\n' /run/user/1000/gnupg/S.gpg-agent.ssh
SH
  write_bash_stub "$TEST_TMPDIR/systemctl" <<'SH'
printf 'args:%s\nsocket:%s\nagent:%s\n' "$*" "${SSH_AUTH_SOCK:-}" "${SSH_AGENT_PID:-}" >"$TEST_TMPDIR/systemctl.log"
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_helper() {
  run env \
    GPGCONF_BIN="$TEST_TMPDIR/gpgconf" \
    SYSTEMCTL_BIN="$TEST_TMPDIR/systemctl" \
    "$@" \
    bash "$SCRIPT"
}

@test "discovers and imports the GnuPG socket when SSH variables are incomplete" {
  run_helper SSH_AGENT_PID=123 SSH_CONNECTION=

  [ "$status" -eq 0 ]
  [ -f "$TEST_TMPDIR/gpgconf.log" ]
  grep -F "args:--user import-environment SSH_AUTH_SOCK" "$TEST_TMPDIR/systemctl.log"
  grep -F "socket:/run/user/1000/gnupg/S.gpg-agent.ssh" "$TEST_TMPDIR/systemctl.log"
  grep -F "agent:" "$TEST_TMPDIR/systemctl.log"
}

@test "keeps an existing forwarded socket when the SSH connection is present" {
  run_helper SSH_AUTH_SOCK=/tmp/forwarded.sock SSH_CONNECTION=client

  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/gpgconf.log" ]
  grep -F "socket:/tmp/forwarded.sock" "$TEST_TMPDIR/systemctl.log"
}
