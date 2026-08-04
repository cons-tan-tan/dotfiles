#!/usr/bin/env bats

setup() {
  if [[ -z ${NH_CLEANUP_SYSTEMD_PACKAGE:-} ]]; then
    skip "systemd units are only built on Linux"
  fi

  SERVICE="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean.service"
  TIMER="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean.timer"
  INSTALLER="$NH_CLEANUP_SYSTEMD_PACKAGE/bin/install-nh-cleanup-systemd"
  RESULT_ROOT_SERVICE="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean-result-roots.service"
  RESULT_ROOT_TIMER="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean-result-roots.timer"
  INSTALLER_SOURCE="nix/packages/nh-cleanup-systemd/install-nh-cleanup-systemd.sh"
}

@test "system service runs the shared policy as the configured user" {
  [ -x "$INSTALLER" ]
  grep -Fqx "User=constantan" "$SERVICE"
  grep -Fqx "Environment=HOME=/home/constantan" "$SERVICE"
  grep -Eq '^ExecStartPre=\+/nix/store/.+/bin/install -d -o root -g root -m 0755 /run/nh-cleanup-systemd$' \
    "$SERVICE"
  grep -Eq '^ExecStartPre=\+/nix/store/.+/bin/touch /run/nh-cleanup-systemd/cleanup.lock$' \
    "$SERVICE"
  grep -Eq '^ExecStartPre=\+/nix/store/.+/bin/chown constantan /run/nh-cleanup-systemd/cleanup.lock$' \
    "$SERVICE"
  grep -Eq '^ExecStartPre=\+/nix/store/.+/bin/chmod 0600 /run/nh-cleanup-systemd/cleanup.lock$' \
    "$SERVICE"
  grep -Eq '^ExecStart=/nix/store/.+/bin/flock --exclusive /run/nh-cleanup-systemd/cleanup.lock /nix/store/.+/bin/nh-clean-growth-runner check /var/lib/nix-store-growth-checker$' \
    "$SERVICE"
  grep -Fqx "StateDirectory=nix-store-growth-checker" "$SERVICE"
  grep -Fqx "TimeoutStartSec=2h" "$SERVICE"
}

@test "one system timer checks both cleanup limits every five minutes" {
  local timer_units=("$NH_CLEANUP_SYSTEMD_PACKAGE"/lib/systemd/system/*.timer)

  grep -Fqx "OnBootSec=5m" "$TIMER"
  grep -Fqx "OnUnitActiveSec=5m" "$TIMER"
  grep -Fqx "Unit=nh-clean.service" "$TIMER"
  ! grep -q "OnCalendar" "$TIMER"
  [ "${#timer_units[@]}" -eq 2 ]
  [ ! -e "$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean-growth-check.timer" ]
}

@test "stale result-root cleanup also avoids the user manager" {
  grep -Fqx "User=constantan" "$RESULT_ROOT_SERVICE"
  grep -Eq '^ExecStart=/nix/store/.+/bin/flock --exclusive /run/nh-cleanup-systemd/cleanup.lock /nix/store/.+/bin/nh-prune-result-roots --keep-minutes 10080$' \
    "$RESULT_ROOT_SERVICE"
  grep -Fqx "OnCalendar=Sun *-*-* 03:00:00" "$RESULT_ROOT_TIMER"
  grep -Fqx "Persistent=true" "$RESULT_ROOT_TIMER"
}

@test "installer switches the system GC root only after successful reload" {
  grep -Fq "/nix/var/nix/gcroots/nh-cleanup-systemd" "$INSTALLER"
  grep -Eq '^readonly unit_tree=/nix/store/.+-nh-cleanup-systemd-units$' "$INSTALLER"
  grep -Fq 'ln -sfnT "$unit_tree" "$next_gcroot"' "$INSTALLER"
  local restart_line root_switch_line
  restart_line=$(grep -n 'systemctl restart' "$INSTALLER" | cut -d: -f1)
  root_switch_line=$(grep -n 'mv -Tf "\$next_gcroot" "\$gcroot"' "$INSTALLER" | cut -d: -f1)
  [ "$restart_line" -lt "$root_switch_line" ]
}

@test "service and installer serialize cleanup with unit and GC root replacement" {
  grep -Fqx 'readonly lock_directory=/run/nh-cleanup-systemd' "$INSTALLER"
  grep -Fqx 'readonly cleanup_lock_file=/run/nh-cleanup-systemd/cleanup.lock' "$INSTALLER"
  grep -Fqx 'readonly installer_lock_file=/run/nh-cleanup-systemd/installer.lock' "$INSTALLER"
  ! grep -Fq '/run/lock' "$INSTALLER"
  grep -Eq '^ExecStart=/nix/store/.+/bin/flock --exclusive /run/nh-cleanup-systemd/cleanup.lock ' \
    "$SERVICE"
  grep -Eq '^ExecStart=/nix/store/.+/bin/flock --exclusive /run/nh-cleanup-systemd/cleanup.lock ' \
    "$RESULT_ROOT_SERVICE"
  grep -Fq 'install -d -o root -g root -m 0755 "$lock_directory"' "$INSTALLER"
  grep -Fq 'flock --exclusive 8' "$INSTALLER"
  grep -Fq 'chown "$cleanup_user" "$cleanup_lock_file"' "$INSTALLER"
  grep -Fq 'chmod 0600 "$cleanup_lock_file"' "$INSTALLER"
  grep -Fq 'trap nh_cleanup_restore_timers EXIT' "$INSTALLER"
  grep -Fq 'trap - EXIT' "$INSTALLER"
  grep -Fq 'nh_cleanup_quiesce_timer nh-clean.timer' "$INSTALLER"
  grep -Fq 'nh_cleanup_quiesce_timer nh-clean-result-roots.timer' "$INSTALLER"
  grep -Fq 'nh_cleanup_wait_until_stopped nh-clean.service' "$INSTALLER"
  grep -Fq 'nh_cleanup_wait_until_stopped nh-clean-result-roots.service' "$INSTALLER"
  local umask_line installer_lock_line timer_stop_line service_wait_line lock_line next_root_line trap_clear_line root_switch_line
  umask_line=$(grep -n 'umask 0077' "$INSTALLER" | cut -d: -f1)
  installer_lock_line=$(grep -n 'flock --exclusive 8' "$INSTALLER" | cut -d: -f1)
  timer_stop_line=$(grep -n 'nh_cleanup_quiesce_timer nh-clean.timer' "$INSTALLER" | cut -d: -f1)
  service_wait_line=$(grep -n 'nh_cleanup_wait_until_stopped nh-clean.service' "$INSTALLER" | cut -d: -f1)
  lock_line=$(grep -n 'flock --exclusive 9' "$INSTALLER" | cut -d: -f1)
  next_root_line=$(grep -n 'ln -sfnT ' "$INSTALLER" | cut -d: -f1)
  trap_clear_line=$(grep -n 'trap - EXIT' "$INSTALLER" | cut -d: -f1)
  root_switch_line=$(grep -n 'mv -Tf "\$next_gcroot" "\$gcroot"' "$INSTALLER" | cut -d: -f1)
  [ "$umask_line" -lt "$installer_lock_line" ]
  [ "$installer_lock_line" -lt "$timer_stop_line" ]
  [ "$umask_line" -lt "$lock_line" ]
  [ "$timer_stop_line" -lt "$service_wait_line" ]
  [ "$service_wait_line" -lt "$lock_line" ]
  [ "$lock_line" -lt "$next_root_line" ]
  [ "$trap_clear_line" -lt "$root_switch_line" ]
}

@test "installer waits through every non-terminal oneshot state" {
  # shellcheck source=../nix/packages/nh-cleanup-systemd/install-nh-cleanup-systemd.sh
  source "$INSTALLER_SOURCE"
  local states="$BATS_TEST_TMPDIR/service-states"
  printf '%s\n' activating active deactivating inactive >"$states"

  systemctl() {
    local state
    [ "$1" = show ]
    state=$(head -n 1 "$states")
    sed -i '1d' "$states"
    printf '%s\n' "$state"
  }
  sleep() { :; }

  nh_cleanup_wait_until_stopped nh-clean.service
  [ ! -s "$states" ]
}

@test "installer propagates a timer stop failure" {
  # shellcheck source=../nix/packages/nh-cleanup-systemd/install-nh-cleanup-systemd.sh
  source "$INSTALLER_SOURCE"

  systemctl() {
    if [ "$1" = show ]; then
      printf '%s\n' active
      return 0
    fi
    [ "$1" = stop ]
    return 1
  }

  ! nh_cleanup_quiesce_timer nh-clean.timer
}

@test "installer reports timer restore failures without hiding the original status" {
  # shellcheck source=../nix/packages/nh-cleanup-systemd/install-nh-cleanup-systemd.sh
  source "$INSTALLER_SOURCE"
  local starts="$BATS_TEST_TMPDIR/timer-starts"
  nh_cleanup_timers_to_restore=(nh-clean.timer nh-clean-result-roots.timer)

  systemctl() {
    [ "$1" = start ]
    printf '%s\n' "$2" >>"$starts"
    [ "$2" != nh-clean.timer ]
  }
  restore_after_failure() {
    false
    nh_cleanup_restore_timers
  }

  run restore_after_failure
  [ "$status" -eq 1 ]
  [[ "$output" == *"warning: failed to restore nh-clean.timer after installer failure"* ]]
  [ "$(wc -l <"$starts")" -eq 2 ]
}
