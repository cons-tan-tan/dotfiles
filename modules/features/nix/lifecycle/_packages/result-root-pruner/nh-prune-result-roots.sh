# shellcheck shell=bash

set -euo pipefail

dry_run=false
keep_minutes=10080

while (($# > 0)); do
  case "$1" in
  --dry-run)
    dry_run=true
    shift
    ;;
  --keep-minutes)
    if (($# < 2)); then
      echo "--keep-minutes requires a value" >&2
      exit 2
    fi
    keep_minutes=$2
    shift 2
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

if [[ ! $keep_minutes =~ ^[1-9][0-9]*$ ]]; then
  echo "--keep-minutes must be a positive integer" >&2
  exit 2
fi

gcroots_dir=${NH_GCROOTS_DIR:-/nix/var/nix/gcroots/auto}
[[ -d $gcroots_dir ]] || exit 0

owner=$("${NH_ID_BIN:-id}" -u)

while IFS= read -r -d '' registration; do
  target=$(readlink -- "$registration") || continue

  # Nix's auto roots normally use absolute destinations. Reject relative
  # paths so cleanup can never escape via the registry directory.
  [[ $target == /* ]] || continue

  case "$target" in
  */.direnv/* | */direnv/layouts/*) continue ;;
  esac

  case "${target##*/}" in
  result | result-*) ;;
  *) continue ;;
  esac

  # A broken registration is expected between deleting a result link and the
  # next daemon GC. It must not abort processing of later registrations.
  [[ -L $target ]] || continue

  store_target=$(readlink -- "$target") || continue
  case "$store_target" in
  /nix/store/*)
    store_suffix=${store_target#/nix/store/}
    [[ -n $store_suffix && $store_suffix != */* ]] || continue
    ;;
  *) continue ;;
  esac

  if ! candidate=$(
    find "$target" \
      -maxdepth 0 \
      -type l \
      -uid "$owner" \
      -mmin "+$keep_minutes" \
      -printf '%p'
  ); then
    continue
  fi
  [[ -n $candidate ]] || continue

  identity=$("${NH_STAT_BIN:-stat}" --format '%d:%i:%u:%Y' -- "$target") || continue
  inode=${identity#*:}
  inode=${inode%%:*}

  # Revalidate the symlink immediately before deletion. The final find also
  # checks the captured inode, owner, type and age to narrow replacement races.
  current_identity=$("${NH_STAT_BIN:-stat}" --format '%d:%i:%u:%Y' -- "$target") || continue
  current_store_target=$(readlink -- "$target") || continue
  if [[ $current_identity != "$identity" || $current_store_target != "$store_target" ]]; then
    echo "skipped changed result link: $target" >&2
    continue
  fi

  if $dry_run; then
    printf 'would remove %s\n' "$target"
  else
    if ! removed=$(
      find "$target" \
        -maxdepth 0 \
        -type l \
        -uid "$owner" \
        -inum "$inode" \
        -mmin "+$keep_minutes" \
        -delete \
        -printf '%p'
    ); then
      echo "skipped vanished result link: $target" >&2
      continue
    fi
    [[ -n $removed ]] && printf 'removed %s\n' "$removed"
  fi
done < <(find "$gcroots_dir" -mindepth 1 -maxdepth 1 -type l -print0)
