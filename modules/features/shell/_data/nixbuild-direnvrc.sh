use_nixbuild_for_ghq_owner() {
  local owner=$1
  local system=$2
  local host=$3
  local max_jobs=$4
  local speed_factor=$5
  local supported_features=$6
  local public_host_key=$7
  local ghq_root
  local owner_root
  local nixbuild_config

  if ! ghq_root="$(command ghq root 2>/dev/null)"; then
    return 0
  fi

  ghq_root=${ghq_root%/}
  owner_root="$ghq_root/github.com/$owner"

  case "$PWD" in
  "$owner_root" | "$owner_root"/*) ;;
  *) return 0 ;;
  esac

  printf -v nixbuild_config '%s\n%s\n%s' \
    "builders = $host $system - $max_jobs $speed_factor $supported_features - $public_host_key" \
    'builders-use-substitutes = true' \
    'max-jobs = 0'

  if [[ -n ${NIX_CONFIG:-} ]]; then
    NIX_CONFIG+=$'\n'
    NIX_CONFIG+=$nixbuild_config
  else
    NIX_CONFIG=$nixbuild_config
  fi
  export NIX_CONFIG
}
