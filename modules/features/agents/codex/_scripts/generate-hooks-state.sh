# Keep discovery outside the caller's home and project, including when switch
# inherits CODEX_HOME from an agent session. Keep a private writable copy of the
# store-managed hooks for inspection and cleanup.
inspection_home=$(mktemp -d "${TMPDIR:-/tmp}/codex-hooks-XXXXXX")
trap 'rm -rf -- "$inspection_home"' EXIT
mkdir -p "$inspection_home/.codex"
install -m 600 "$hooks_source" "$inspection_home/.codex/hooks.json"
printf '[features]\nhooks = true\n' >"$inspection_home/.codex/config.toml"

cd "$inspection_home"
env -u CODEX_HOME \
  HOME="$inspection_home" \
  XDG_CONFIG_HOME="$inspection_home/.config" \
  "$config_helper" generate-managed-hook-state \
  --codex-bin "$codex_bin" \
  --manifest "$manifest" \
  --hooks-json-path "$hooks_path" \
  --cwd "$inspection_home"
