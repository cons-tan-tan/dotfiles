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
