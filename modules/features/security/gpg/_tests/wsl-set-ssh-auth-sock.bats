#!/usr/bin/env bats

setup() {
  if [[ -z ${GPG_WSL_AUTH_SOCK_TEST_BIN:-} ]]; then
    skip "GPG_WSL_AUTH_SOCK_TEST_BIN is only available in the Nix-backed Bats check"
  fi
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_helper() {
  run env "$@" "$GPG_WSL_AUTH_SOCK_TEST_BIN"
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
