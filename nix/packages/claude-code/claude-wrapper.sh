export PATH="$NODE_BIN:$PATH"

if [ "${HERDR_ENV:-}" = "1" ]; then
  exec -a "$0" "$CLAUDE_BASE" --effort xhigh --plugin-dir "$HERDR_PLUGIN" "$@"
fi

exec -a "$0" "$CLAUDE_BASE" --effort xhigh "$@"
