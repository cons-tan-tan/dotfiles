options_enabled=1
for argument in "$@"; do
  if [ "$options_enabled" -eq 0 ]; then
    continue
  fi
  if [ "$argument" = "--" ]; then
    options_enabled=0
    continue
  fi

  while IFS= read -r forbidden; do
    case "$forbidden" in
    --*)
      if [ "$argument" = "$forbidden" ] || [[ $argument == "$forbidden="* ]]; then
        printf 'fd: option %s is disabled for agents\n' "$forbidden" >&2
        exit 2
      fi
      ;;
    esac
  done <"$FD_FORBIDDEN_OPTIONS"

  if [[ $argument != -[^-]* ]]; then
    continue
  fi

  short_options="${argument#-}"
  while [ -n "$short_options" ]; do
    option="${short_options:0:1}"
    short_options="${short_options:1}"

    while IFS= read -r forbidden; do
      if [ "$forbidden" = "-$option" ]; then
        printf 'fd: option %s is disabled for agents\n' "$forbidden" >&2
        exit 2
      fi
    done <"$FD_FORBIDDEN_OPTIONS"

    # These short options consume the rest of the token as their value, so a
    # later x/X belongs to that value rather than to the option cluster.
    case "$option" in
    d | E | t | e | S | o | c | j | C)
      break
      ;;
    esac
  done
done

exec "$FD_BIN" "$@"
