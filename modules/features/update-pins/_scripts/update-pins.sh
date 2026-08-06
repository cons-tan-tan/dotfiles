#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update-pins [--check] [--list] [TARGET ...]

Run package-owned passthru.updateScript commands. With no TARGET, all managed
packages are updated. Commands run in a disposable clone, and their combined
diff is applied only after every target succeeds. --check reports that diff
without changing the original worktree.
EOF
}

list_targets() {
  jq -r 'to_entries[] | "\(.key)\t\(.value.description)"' \
    "$UPDATE_PINS_REGISTRY"
}

run_target() {
  local target=$1
  local -a update_command

  if ! jq -e --arg target "$target" 'has($target)' \
    "$UPDATE_PINS_REGISTRY" >/dev/null; then
    printf 'update-pins: unknown target: %s\n' "$target" >&2
    return 2
  fi

  mapfile -d '' -t update_command < <(
    jq -j --arg target "$target" \
      '.[$target].command[] | ., "\u0000"' \
      "$UPDATE_PINS_REGISTRY"
  )
  printf 'update-pins: updating %s\n' "$target"
  "${update_command[@]}"
}

run_targets() {
  local target
  for target in "$@"; do
    run_target "$target"
  done
}

check=false
list=false
targets=()
for argument in "$@"; do
  case "$argument" in
  --check) check=true ;;
  --list) list=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    printf 'update-pins: unknown option: %s\n' "$argument" >&2
    usage >&2
    exit 2
    ;;
  *) targets+=("$argument") ;;
  esac
done

if $list; then
  list_targets
  exit 0
fi

if ((${#targets[@]} == 0)); then
  mapfile -t targets < <(jq -r 'keys[]' "$UPDATE_PINS_REGISTRY")
fi

for target in "${targets[@]}"; do
  if ! jq -e --arg target "$target" 'has($target)' \
    "$UPDATE_PINS_REGISTRY" >/dev/null; then
    printf 'update-pins: unknown target: %s\n' "$target" >&2
    exit 2
  fi
done

repo_root=$(git rev-parse --show-toplevel)
if [[ -n $(git -C "$repo_root" status --short) ]]; then
  printf 'update-pins: updating requires a clean worktree\n' >&2
  exit 2
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/update-pins.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
git clone --quiet --no-hardlinks "$repo_root" "$work_dir/repo"

(
  cd "$work_dir/repo"
  run_targets "${targets[@]}"
)

clone_status=$(git -C "$work_dir/repo" status --short)
if $check; then
  if [[ -n $clone_status ]]; then
    printf 'update-pins: managed pins are out of date\n' >&2
    git -C "$work_dir/repo" status --short >&2
    git -C "$work_dir/repo" diff -- >&2
    exit 1
  fi
  exit 0
fi

mapfile -t untracked < <(
  git -C "$work_dir/repo" ls-files --others --exclude-standard
)
if ((${#untracked[@]} > 0)); then
  printf 'update-pins: update scripts created unsupported untracked files:\n' >&2
  printf '  %s\n' "${untracked[@]}" >&2
  exit 1
fi

patch_file=$work_dir/update.patch
git -C "$work_dir/repo" diff --binary HEAD -- >"$patch_file"
if [[ ! -s $patch_file ]]; then
  exit 0
fi

# Checking before applying keeps the clean source tree untouched if the patch
# cannot be transferred back from the disposable clone.
git -C "$repo_root" apply --check "$patch_file"
git -C "$repo_root" apply "$patch_file"
