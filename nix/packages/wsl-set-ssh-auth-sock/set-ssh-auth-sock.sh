: "${GPGCONF_BIN:=gpgconf}"
: "${SYSTEMCTL_BIN:=systemctl}"

if [ -z "${SSH_AUTH_SOCK:-}" ] || [ -z "${SSH_CONNECTION:-}" ]; then
  unset SSH_AGENT_PID
  if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
    sock="$("$GPGCONF_BIN" --list-dirs agent-ssh-socket)"
    export SSH_AUTH_SOCK="$sock"
  fi
fi

"$SYSTEMCTL_BIN" --user import-environment SSH_AUTH_SOCK
