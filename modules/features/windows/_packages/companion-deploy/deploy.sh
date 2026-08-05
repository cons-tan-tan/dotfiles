set -euo pipefail

manifest=${1:?usage: windows-companion-deploy MANIFEST}
root_prefix=${WINDOWS_COMPANION_DEPLOY_ROOT_PREFIX:?missing deployment root prefix}
mv_bin=${WINDOWS_COMPANION_DEPLOY_MV_BIN:?missing mv executable}
rsync_bin=${WINDOWS_COMPANION_DEPLOY_RSYNC_BIN:?missing rsync executable}
root=$(jq -er '.root | select(type == "string")' "$manifest")
username=${root#"$root_prefix"/}

if [[ $root == "$username" || -z $username || $username == */* || $username == . || $username == .. ]]; then
  echo "windows-companion-deploy: Windows home must be one user below $root_prefix: $root" >&2
  exit 1
fi

if [[ ! -d $root || -L $root || $(realpath -e -- "$root") != "$root" ]]; then
  echo "windows-companion-deploy: unsafe or missing Windows home: $root" >&2
  exit 1
fi

validate_relative() {
  local value=$1
  if [[ -z $value || $value == /* || $value == */ || $value == *//* || "/$value/" == *"/./"* || "/$value/" == *"/../"* || $value == *$'\n'* || $value == *$'\t'* ]]; then
    echo "windows-companion-deploy: unsafe relative path: $value" >&2
    return 1
  fi
}

active_stage=
active_backup=
rollback_source=
rollback_target=
rollback_remove_target=0

remove_tree() {
  local path=$1
  if [[ -e $path ]]; then
    chmod -R u+w -- "$path" 2>/dev/null || true
    rm -rf -- "$path"
  fi
}

cleanup_active_stage() {
  local status=$?
  local restored=1
  trap - EXIT HUP INT TERM

  if [[ -n $rollback_target ]]; then
    if ((rollback_remove_target)); then
      remove_tree "$rollback_target"
    elif [[ -n $rollback_source && -d $rollback_source ]]; then
      if ! chmod -R u+w -- "$rollback_target" || ! "$rsync_bin" -aLc --chmod=u+w --delete --delay-updates -- "$rollback_source/" "$rollback_target/"; then
        echo "windows-companion-deploy: rollback failed; recovery snapshot kept at $rollback_source" >&2
        restored=0
        status=1
      fi
    fi
  fi
  if [[ -n $active_stage && -e $active_stage ]]; then
    remove_tree "$active_stage"
  fi
  if ((restored)) && [[ -n $active_backup && -e $active_backup ]]; then
    remove_tree "$active_backup"
  fi
  exit "$status"
}

arm_stage_cleanup() {
  active_stage=$1
  active_backup=
  rollback_source=
  rollback_target=
  rollback_remove_target=0
  trap cleanup_active_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

disarm_stage_cleanup() {
  active_stage=
  active_backup=
  rollback_source=
  rollback_target=
  rollback_remove_target=0
  trap - EXIT HUP INT TERM
}

ensure_directory() {
  local relative=$1
  local current=$root
  local component
  validate_relative "$relative"
  IFS=/ read -r -a components <<<"$relative"
  for component in "${components[@]}"; do
    if [[ -z $component || $component == . || $component == .. ]]; then
      echo "windows-companion-deploy: unsafe path component: $relative" >&2
      return 1
    fi
    current="$current/$component"
    if [[ -L $current ]]; then
      echo "windows-companion-deploy: destination traverses a symlink: $current" >&2
      return 1
    fi
    if [[ -e $current && ! -d $current ]]; then
      echo "windows-companion-deploy: destination component is not a directory: $current" >&2
      return 1
    fi
    if [[ ! -e $current ]]; then
      mkdir -- "$current"
    fi
  done
}

while IFS= read -r relative; do
  ensure_directory "$relative"
done < <(jq -er '.directories[] | select(type == "string")' "$manifest")

while IFS=$'\t' read -r source destination mode; do
  validate_relative "$destination"
  parent=${destination%/*}
  if [[ $parent == "$destination" ]]; then
    parent=.
  else
    ensure_directory "$parent"
  fi
  target="$root/$destination"
  if [[ -L $target || -d $target ]]; then
    echo "windows-companion-deploy: unsafe file destination: $target" >&2
    exit 1
  fi
  stage=$(mktemp "$root/$parent/.deploy-file.XXXXXX")
  arm_stage_cleanup "$stage"
  if ! install -m "$mode" -- "$source" "$stage"; then
    exit 1
  fi
  "$mv_bin" -f -T -- "$stage" "$target"
  disarm_stage_cleanup
done < <(jq -er '.files[] | [.source, .destination, (.mode // "0644")] | @tsv' "$manifest")

while IFS= read -r encoded; do
  tree=$(printf '%s' "$encoded" | base64 --decode)
  source=$(jq -er '.source' <<<"$tree")
  destination=$(jq -er '.destination' <<<"$tree")
  validate_relative "$destination"
  parent=${destination%/*}
  base=${destination##*/}
  if [[ $parent == "$destination" ]]; then
    parent=.
  else
    ensure_directory "$parent"
  fi
  target="$root/$destination"
  if [[ -L $target || (-e $target && ! -d $target) ]]; then
    echo "windows-companion-deploy: unsafe tree destination: $target" >&2
    exit 1
  fi
  stage=$(mktemp -d "$root/$parent/.${base}.new.XXXXXX")
  arm_stage_cleanup "$stage"
  rsync_args=(-aL --chmod=u+w --delete --delete-excluded)
  while IFS= read -r exclude; do
    rsync_args+=("--exclude=$exclude")
  done < <(jq -er '.excludes[]?' <<<"$tree")
  if ! "$rsync_bin" "${rsync_args[@]}" -- "$source/" "$stage/"; then
    exit 1
  fi
  backup=$(mktemp -d "$root/$parent/.${base}.backup.XXXXXX")
  active_backup=$backup
  if [[ -e $target ]]; then
    mkdir -- "$backup/original"
    if ! "$rsync_bin" -aL --chmod=u+w --delete -- "$target/" "$backup/original/"; then
      exit 1
    fi
    rollback_source="$backup/original"
  else
    mkdir -- "$target"
    rollback_remove_target=1
  fi
  rollback_target=$target

  # DrvFS rejects renameat2 flags, so publish complete files with ordinary
  # same-directory renames and restore the snapshot on failure or signals.
  if ! chmod -R u+w -- "$target" || ! "$rsync_bin" -aLc --chmod=u+w --delete-delay --delay-updates -- "$stage/" "$target/"; then
    exit 1
  fi
  rollback_target=
  remove_tree "$stage"
  remove_tree "$backup"
  disarm_stage_cleanup
done < <(jq -r '.trees[] | @base64' "$manifest")
