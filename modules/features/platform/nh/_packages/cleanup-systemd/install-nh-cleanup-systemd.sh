#!/usr/bin/env bash

nh_cleanup_timers_to_restore=()

nh_cleanup_unit_state() {
  local unit=$1
  local state

  if ! state=$("${systemctl_command:-systemctl}" show --property=ActiveState --value "$unit"); then
    echo "failed to query systemd state for $unit" >&2
    return 1
  fi
  if [[ -z $state ]]; then
    echo "systemd returned an empty ActiveState for $unit" >&2
    return 1
  fi
  printf '%s\n' "$state"
}

nh_cleanup_wait_until_stopped() {
  local unit=$1
  local state

  while true; do
    state=$(nh_cleanup_unit_state "$unit")
    if [[ $state == inactive || $state == failed ]]; then
      return 0
    fi
    sleep 1
  done
}

nh_cleanup_quiesce_timer() {
  local unit=$1
  local state

  state=$(nh_cleanup_unit_state "$unit")
  if [[ $state == inactive || $state == failed ]]; then
    return 0
  fi

  nh_cleanup_timers_to_restore+=("$unit")
  if ! "${systemctl_command:-systemctl}" stop "$unit"; then
    echo "failed to stop $unit" >&2
    return 1
  fi
  nh_cleanup_wait_until_stopped "$unit"
}

nh_cleanup_restore_timers() {
  local original_status=$?
  local unit

  for unit in "${nh_cleanup_timers_to_restore[@]}"; do
    if ! "${systemctl_command:-systemctl}" start "$unit" >/dev/null; then
      echo "warning: failed to restore $unit after installer failure" >&2
    fi
  done
  return "$original_status"
}

nh_cleanup_main() {
  if [[ ${allow_unprivileged:-false} != true ]] && ((EUID != 0)); then
    echo "install-nh-cleanup-systemd must run as root" >&2
    return 1
  fi

  umask 0077
  if [[ ${manage_ownership:-true} == true ]]; then
    install -d -o root -g root -m 0755 "$lock_directory"
  else
    install -d -m 0755 "$lock_directory"
  fi
  touch "$installer_lock_file"
  chmod 0600 "$installer_lock_file"
  exec 8<>"$installer_lock_file"
  flock --exclusive 8

  touch "$cleanup_lock_file"
  if [[ ${manage_ownership:-true} == true ]]; then
    chown "$cleanup_user" "$cleanup_lock_file"
  fi
  chmod 0600 "$cleanup_lock_file"
  exec 9<>"$cleanup_lock_file"

  nh_cleanup_timers_to_restore=()
  trap nh_cleanup_restore_timers EXIT
  nh_cleanup_quiesce_timer nh-clean.timer
  nh_cleanup_quiesce_timer nh-clean-result-roots.timer
  nh_cleanup_wait_until_stopped nh-clean.service
  nh_cleanup_wait_until_stopped nh-clean-result-roots.service
  flock --exclusive 9

  install -d -m 0755 "$(dirname "$gcroot")"
  # Keep the old closure rooted until every unit has been installed and
  # successfully reloaded. A failed update leaves both generations safe.
  ln -sfnT "$unit_tree" "$next_gcroot"
  install -D -m 0644 "$source_directory/nh-clean.service" \
    "$target_directory/nh-clean.service"
  install -D -m 0644 "$source_directory/nh-clean.timer" \
    "$target_directory/nh-clean.timer"
  install -D -m 0644 "$source_directory/nh-clean-result-roots.service" \
    "$target_directory/nh-clean-result-roots.service"
  install -D -m 0644 "$source_directory/nh-clean-result-roots.timer" \
    "$target_directory/nh-clean-result-roots.timer"
  "${systemctl_command:-systemctl}" daemon-reload
  "${systemctl_command:-systemctl}" enable nh-clean.timer nh-clean-result-roots.timer
  "${systemctl_command:-systemctl}" restart nh-clean.timer nh-clean-result-roots.timer
  trap - EXIT
  mv -Tf "$next_gcroot" "$gcroot"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  nh_cleanup_main "$@"
fi
