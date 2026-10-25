profile_cwd=$PWD
case "${1:-}" in
--cwd)
  [[ $# == 2 ]] || {
    printf 'agent-skill-profile: expected --cwd DIRECTORY\n' >&2
    exit 2
  }
  profile_cwd=$2
  ;;
--codex)
  shift
  # Only directory options affect selection. Keep prompt text and option values opaque.
  while (($#)); do
    case "$1" in
    --) break ;;
    -C | --cd)
      [[ $# -ge 2 ]] || {
        printf 'agent-skill-profile: missing directory for %s\n' "$1" >&2
        exit 2
      }
      profile_cwd=$2
      shift
      ;;
    --cd=*) profile_cwd=${1#--cd=} ;;
    -C?*) profile_cwd=${1#-C} ;;
    -c | --config | -p | --profile | -m | --model | -i | --image | -s | --sandbox | -a | --ask-for-approval | --enable | --disable | --add-dir | --local-provider | --remote | --remote-auth-token-env)
      [[ $# -ge 2 ]] || {
        printf 'agent-skill-profile: missing value for %s\n' "$1" >&2
        exit 2
      }
      shift
      ;;
    esac
    shift
  done
  ;;
"") ;;
*)
  printf 'agent-skill-profile: expected --cwd DIRECTORY or --codex ARGS...\n' >&2
  exit 2
  ;;
esac

CDPATH='' cd -P -- "$profile_cwd"
profile_candidates=("$PWD")
# A linked worktree can live outside ghq; the first entry is the main checkout.
if IFS= read -r -d '' profile_worktree < <(git worktree list --porcelain -z 2>/dev/null) && [[ $profile_worktree == 'worktree '* ]]; then
  profile_candidates+=("$(realpath -e -- "${profile_worktree#worktree }")")
fi

profile_roots=$(ghq root --all)
while IFS= read -r profile_root; do
  [[ -n $profile_root ]] || continue
  for profile_scope in "${PROFILE_SCOPES[@]}"; do
    profile_prefix=$(realpath -m -- "$profile_root/$profile_scope")
    for profile_candidate in "${profile_candidates[@]}"; do
      if [[ $profile_candidate == "$profile_prefix" || $profile_candidate == "$profile_prefix/"* ]]; then
        printf 'fine-grained\n'
        exit 0
      fi
    done
  done
done <<<"$profile_roots"
printf 'standard\n'
