export PATH="$NODE_BIN:$PATH"

claude_args=(--effort xhigh)
if [[ -n ${COMMIT_PROFILE_SELECTOR:-} ]]; then
  commit_profile=$("$COMMIT_PROFILE_SELECTOR" --cwd "$PWD")
  claude_args+=(--add-dir "$COMMIT_PROFILE_ARTIFACTS/$commit_profile")
fi

if [ "${HERDR_ENV:-}" = "1" ]; then
  claude_args+=(--plugin-dir "$HERDR_PLUGIN")
fi

exec -a "$0" "$CLAUDE_BASE" "${claude_args[@]}" "$@"
