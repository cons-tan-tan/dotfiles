# shellcheck shell=bash

# direnvrc runs before .envrc. Extend source_env to load local settings last,
# retaining upstream loading and watch behavior without patching direnv.
_dotfiles_source_env_definition=$(declare -f source_env)
eval "${_dotfiles_source_env_definition/source_env/_dotfiles_source_env}"
unset _dotfiles_source_env_definition

source_env() {
  if [[ -n ${_dotfiles_envrc_local-} ]]; then
    # Bash dynamic scope lets nested source_env calls record an explicit load.
    if [[ ${1/#\~/$HOME} -ef $_dotfiles_envrc_local ]]; then
      _dotfiles_envrc_local_read=true
    fi
    _dotfiles_source_env "$@"
    return
  fi

  local _dotfiles_envrc_local _dotfiles_envrc_local_read=false
  _dotfiles_envrc_local=$(expand_path "${1/#\~/$HOME}")
  if [[ -d $_dotfiles_envrc_local ]]; then
    _dotfiles_envrc_local+=/.envrc
  fi
  _dotfiles_envrc_local+=.local

  # Keep this outside a conditional so strict_env still stops on failure.
  _dotfiles_source_env "$@"
  local status=$?
  if ((status != 0)); then
    return "$status"
  fi

  if [[ $_dotfiles_envrc_local_read == false ]]; then
    source_env_if_exists "$_dotfiles_envrc_local"
  fi
}
