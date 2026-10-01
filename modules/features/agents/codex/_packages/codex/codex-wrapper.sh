# Use the caller's PATH and environment rather than the shared server's.
# daemon_auto_start=false still connects to an existing server; opt out explicitly.
# The CLI rejects duplicate --no-daemon flags. Ignore prompt arguments after --.
for arg in "$@"; do
  case "$arg" in
  --no-daemon) exec "$CODEX_BIN" "$@" ;;
  --) break ;;
  esac
done

exec "$CODEX_BIN" --no-daemon "$@"
