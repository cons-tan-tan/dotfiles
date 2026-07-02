: "${HERDR_BIN:?HERDR_BIN must be set}"

is_tty_stdout() {
  if [ "${HERDR_WRAPPER_ASSUME_TTY:-}" = "1" ]; then
    return 0
  fi
  [ -t 1 ]
}

needs_focus_reporting_workaround=false
case "${1-}" in
"" | --session | --no-session | --remote)
  needs_focus_reporting_workaround=true
  ;;
session)
  if [ "${2-}" = attach ]; then
    needs_focus_reporting_workaround=true
  fi
  ;;
esac

# Windows Terminal 1.24 + WSL では focus reporting (?1004) が有効な
# herdr pane へ戻ると IME が日本語入力へ切り替わらなくなることがある。
# 他の terminal では herdr の focus tracking を維持したいので、
# Windows Terminal 上の WSL にだけ workaround を限定する。
if [ "$needs_focus_reporting_workaround" = true ] &&
  [ -n "${WT_SESSION:-}" ] &&
  [ -n "${WSL_DISTRO_NAME:-}" ] &&
  is_tty_stdout; then
  if [ -n "${HERDR_WRAPPER_TRACE:-}" ]; then
    echo "workaround" >>"$HERDR_WRAPPER_TRACE"
  fi
  (
    sleep 1
    printf '\033[?1004l' >/dev/tty 2>/dev/null || true
  ) &
fi

exec "$HERDR_BIN" "$@"
