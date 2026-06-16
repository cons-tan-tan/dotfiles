#!/usr/bin/env bash
# Sync the repo-managed Nix daemon settings into /etc/nix/nix.custom.conf.
set -euo pipefail

begin_marker="# BEGIN cons-tan-tan/dotfiles apply-nix-settings"
end_marker="# END cons-tan-tan/dotfiles apply-nix-settings"

target=${APPLY_NIX_SETTINGS_CONF:-/etc/nix/nix.custom.conf}
nix_conf=${APPLY_NIX_SETTINGS_NIX_CONF:-/etc/nix/nix.conf}
snippet=${APPLY_NIX_SETTINGS_SNIPPET:?APPLY_NIX_SETTINGS_SNIPPET is required}
sudo_bin=${APPLY_NIX_SETTINGS_SUDO:-/usr/bin/sudo}
dry_run=0
check=0

usage() {
  cat <<'EOF'
Usage: apply-nix-settings [--check] [--dry-run]

Syncs the managed block in /etc/nix/nix.custom.conf. Set
APPLY_NIX_SETTINGS_CONF to test or target another file. Set
APPLY_NIX_SETTINGS_NIX_CONF to test the nix.conf include check.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --check)
    check=1
    ;;
  --dry-run)
    dry_run=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "apply-nix-settings: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if [ ! -f "$snippet" ]; then
  echo "apply-nix-settings: snippet not found: $snippet" >&2
  exit 1
fi

normalize_existing_dir_path() {
  local path=$1
  local dir base
  dir=$(dirname "$path")
  base=$(basename "$path")
  if [ ! -d "$dir" ]; then
    return 1
  fi
  (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
}

if [ "$target" = "/etc/nix/nix.custom.conf" ] || [ -n "${APPLY_NIX_SETTINGS_NIX_CONF:-}" ]; then
  if [ ! -f "$nix_conf" ]; then
    echo "apply-nix-settings: nix.conf not found: $nix_conf" >&2
    echo "apply-nix-settings: manage Nix daemon settings another way, or install Determinate Nix" >&2
    exit 1
  fi
  expected_include=$(normalize_existing_dir_path "$target") || {
    echo "apply-nix-settings: target directory does not exist: $(dirname "$target")" >&2
    exit 1
  }
  include_found=0
  nix_conf_dir=$(dirname "$nix_conf")
  while read -r directive include_path _; do
    case "$directive" in
    include | '!include')
      case "$include_path" in
      /*)
        candidate_include=$include_path
        ;;
      *)
        candidate_include=$nix_conf_dir/$include_path
        ;;
      esac
      if [ "$(normalize_existing_dir_path "$candidate_include" 2>/dev/null || true)" = "$expected_include" ]; then
        include_found=1
        break
      fi
      ;;
    esac
  done <"$nix_conf"
  if [ "$include_found" -ne 1 ]; then
    echo "apply-nix-settings: $nix_conf does not include $target" >&2
    echo "apply-nix-settings: add '!include $(basename "$target")' beside nix.conf or manage Nix daemon settings another way" >&2
    exit 1
  fi
fi

tmpdir=$(mktemp -d)
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

current="$tmpdir/current"
desired="$tmpdir/desired"

if [ -f "$target" ]; then
  cp "$target" "$current"
else
  : >"$current"
fi

marker_error=$(
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin {
      if (seen_begin || seen_end) {
        print "expected exactly one matching BEGIN/END pair, or no managed block"
        exit 1
      }
      seen_begin = 1
      next
    }
    $0 == end {
      if (!seen_begin || seen_end) {
        print "expected END only after BEGIN"
        exit 1
      }
      seen_end = 1
      next
    }
    END {
      if (seen_begin != seen_end) {
        print "expected matching BEGIN/END markers"
        exit 1
      }
    }
  ' "$current"
) || true
if [ -n "$marker_error" ]; then
  echo "apply-nix-settings: malformed managed block in $target" >&2
  echo "apply-nix-settings: $marker_error" >&2
  exit 1
fi

if grep -Fqx "$begin_marker" "$current"; then
  awk -v begin="$begin_marker" -v end="$end_marker" -v snippet="$snippet" '
    $0 == begin {
      print begin
      while ((getline line < snippet) > 0) {
        print line
      }
      close(snippet)
      print end
      in_block = 1
      next
    }
    in_block && $0 == end {
      in_block = 0
      next
    }
    !in_block {
      print
    }
  ' "$current" >"$desired"
else
  {
    cat "$current"
    if [ -s "$current" ]; then
      printf '\n'
    fi
    printf '%s\n' "$begin_marker"
    cat "$snippet"
    printf '%s\n' "$end_marker"
  } >"$desired"
fi

if cmp -s "$current" "$desired"; then
  echo "apply-nix-settings: $target is already up to date"
  exit 0
fi

if [ "$check" -eq 1 ]; then
  echo "apply-nix-settings: $target is not up to date" >&2
  diff -u "$current" "$desired" || true
  exit 1
fi

if [ "$dry_run" -eq 1 ]; then
  diff -u "$current" "$desired" || true
  exit 0
fi

target_dir=$(dirname "$target")
needs_sudo=0
if [ ! -d "$target_dir" ]; then
  parent_dir=$(dirname "$target_dir")
  if [ ! -w "$parent_dir" ]; then
    needs_sudo=1
  fi
elif [ -e "$target" ]; then
  if [ ! -w "$target" ]; then
    needs_sudo=1
  fi
elif [ ! -w "$target_dir" ]; then
  needs_sudo=1
fi

if [ "$needs_sudo" -eq 1 ] && [ "${APPLY_NIX_SETTINGS_ELEVATED:-0}" != "1" ]; then
  if [ ! -x "$sudo_bin" ]; then
    echo "apply-nix-settings: $target requires root, and sudo is not available: $sudo_bin" >&2
    exit 1
  fi
  exec "$sudo_bin" \
    APPLY_NIX_SETTINGS_ELEVATED=1 \
    APPLY_NIX_SETTINGS_CONF="$target" \
    APPLY_NIX_SETTINGS_NIX_CONF="$nix_conf" \
    APPLY_NIX_SETTINGS_SNIPPET="$snippet" \
    "$0" "$@"
fi

install -d -m 0755 "$target_dir"
install -m 0644 "$desired" "$target"

echo "apply-nix-settings: wrote $target"
echo "apply-nix-settings: restart the Nix daemon for changes to take effect"
case "$(uname -s)" in
Darwin)
  echo "  sudo launchctl kickstart -k system/org.nixos.nix-daemon"
  ;;
Linux)
  if [ -d /run/systemd/system ]; then
    echo "  sudo systemctl restart nix-daemon.service"
  else
    echo "  restart the WSL distro, or restart nix-daemon using your distro's service manager"
  fi
  ;;
esac
