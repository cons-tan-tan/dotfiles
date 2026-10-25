# Use the caller's PATH and environment rather than the shared server's.
# daemon_auto_start=false still connects to an existing server; opt out explicitly.
# The CLI rejects duplicate --no-daemon flags. Ignore prompt arguments after --.
codex_args=()
if [[ -n ${COMMIT_PROFILE_SELECTOR:-} ]]; then
  # shortcut: selection precedes resume; use a session hook if restored cwd must change the profile.
  commit_profile=$("$COMMIT_PROFILE_SELECTOR" --codex "$@")
  codex_args+=(-c "$(<"$COMMIT_PROFILE_ARTIFACTS/$commit_profile/codex-override")")
fi
codex_embedded=(--no-daemon)
for arg in "$@"; do
  case "$arg" in
  --no-daemon)
    codex_embedded=()
    break
    ;;
  --) break ;;
  esac
done

exec "$CODEX_BIN" "${codex_embedded[@]}" "${codex_args[@]}" "$@"
