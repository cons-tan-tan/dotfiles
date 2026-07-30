write_bash_stub() {
  local stub_path=$1
  local bash_path=$BASH

  # Nix build sandboxes have no /usr/bin/env, so stubs use Bash directly.
  if [[ $bash_path != /* ]]; then
    bash_path=$(type -P "$bash_path")
  fi

  printf '#!%s\n' "$bash_path" >"$stub_path"
  cat >>"$stub_path"
  chmod +x "$stub_path"
}

assert_agent_fd_policy() {
  local fd_path=$1
  local option

  for option in --exec --exec=echo --exec-batch -x -X -xecho -Xecho -HIx -HIX; do
    run "$fd_path" "$option" echo '{}'
    [ "$status" -eq 2 ]
    [[ $output == *"is disabled for agents"* ]]
  done

  run "$fd_path" -HEx
  [ "$status" -eq 0 ]

  mkdir -p "$TEST_TMPDIR/x"
  run "$fd_path" -C"$TEST_TMPDIR/x" --version
  [ "$status" -eq 0 ]

  run "$fd_path" -- --exec
  [ "$status" -eq 0 ]
}
