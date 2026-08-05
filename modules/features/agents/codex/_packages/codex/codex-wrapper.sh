if [ "${HERDR_ENV:-}" = "1" ]; then
  exec "$CODEX_BIN" -c "$HERDR_SKILL_OVERRIDE" "$@"
fi

exec "$CODEX_BIN" "$@"
