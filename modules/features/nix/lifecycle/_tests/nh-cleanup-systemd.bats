#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  if [[ -z ${NH_CLEANUP_SYSTEMD_PACKAGE:-} ]]; then
    skip "systemd units are only built on Linux"
  fi

  SERVICE="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean.service"
  TIMER="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean.timer"
  INSTALLER="$NH_CLEANUP_SYSTEMD_PACKAGE/bin/install-nh-cleanup-systemd"
  RESULT_ROOT_SERVICE="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean-result-roots.service"
  RESULT_ROOT_TIMER="$NH_CLEANUP_SYSTEMD_PACKAGE/lib/systemd/system/nh-clean-result-roots.timer"
  INSTALLER_SOURCE="$DOTFILES_TEST_REPO_ROOT/modules/features/nix/lifecycle/_packages/cleanup-systemd/install-nh-cleanup-systemd.sh"
  INSTALL_TARGET="$BATS_TEST_TMPDIR/etc/systemd/system"
  INSTALL_GCROOT="$BATS_TEST_TMPDIR/gcroots/nh-cleanup-systemd"
  INSTALL_LOCK_DIRECTORY="$BATS_TEST_TMPDIR/run/nh-cleanup-systemd"
  SYSTEMCTL_LOG="$BATS_TEST_TMPDIR/systemctl.log"
  SYSTEMCTL_STATE_DIRECTORY="$BATS_TEST_TMPDIR/systemctl-state"
  SYSTEMCTL_PROBE="$BATS_TEST_TMPDIR/systemctl"

  mkdir -p "$SYSTEMCTL_STATE_DIRECTORY"
  printf '%s\n' \
    '#!/bin/sh' \
    'set -eu' \
    'printf "systemctl %s\n" "$*" >>"$SYSTEMCTL_LOG"' \
    'command_name=$1' \
    'if [ -f "$NH_CLEANUP_TEST_LOCK_DIRECTORY/installer.lock" ] && [ -f "$NH_CLEANUP_TEST_LOCK_DIRECTORY/cleanup.lock" ]; then' \
    '  printf "locks=present\n" >>"$SYSTEMCTL_LOG"' \
    'fi' \
    'if [ "$command_name" = daemon-reload ]; then' \
    '  [ -L "$NH_CLEANUP_TEST_GCROOT.next" ] && printf "next-root=present\n" >>"$SYSTEMCTL_LOG"' \
    '  [ -f "$NH_CLEANUP_TEST_TARGET_DIRECTORY/nh-clean.service" ] && printf "units=present\n" >>"$SYSTEMCTL_LOG"' \
    'fi' \
    'if [ "$command_name" = restart ]; then' \
    '  if [ -e "$NH_CLEANUP_TEST_GCROOT" ] || [ -L "$NH_CLEANUP_TEST_GCROOT" ]; then' \
    '    printf "restart-root=present\n" >>"$SYSTEMCTL_LOG"' \
    '  else' \
    '    printf "restart-root=absent\n" >>"$SYSTEMCTL_LOG"' \
    '  fi' \
    'fi' \
    'if [ "${SYSTEMCTL_FAIL_COMMAND:-}" = "$command_name" ]; then' \
    '  exit 42' \
    'fi' \
    'case "$command_name" in' \
    'show)' \
    '  unit=$4' \
    '  state_file="$SYSTEMCTL_STATE_DIRECTORY/$unit"' \
    '  if [ -f "$state_file" ]; then' \
    '    cat "$state_file"' \
    '  elif [ "${unit%.timer}" != "$unit" ]; then' \
    '    printf "active\n"' \
    '  else' \
    '    printf "inactive\n"' \
    '  fi' \
    '  ;;' \
    'stop)' \
    '  printf "inactive\n" >"$SYSTEMCTL_STATE_DIRECTORY/$2"' \
    '  ;;' \
    'start)' \
    '  printf "active\n" >"$SYSTEMCTL_STATE_DIRECTORY/$2"' \
    '  ;;' \
    'esac' \
    >"$SYSTEMCTL_PROBE"
  chmod +x "$SYSTEMCTL_PROBE"
}

invoke_installer() {
  env \
    NH_CLEANUP_TEST_GCROOT="$INSTALL_GCROOT" \
    NH_CLEANUP_TEST_LOCK_DIRECTORY="$INSTALL_LOCK_DIRECTORY" \
    NH_CLEANUP_TEST_SYSTEMCTL_BIN="$SYSTEMCTL_PROBE" \
    NH_CLEANUP_TEST_TARGET_DIRECTORY="$INSTALL_TARGET" \
    SYSTEMCTL_FAIL_COMMAND="${SYSTEMCTL_FAIL_COMMAND:-}" \
    SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
    SYSTEMCTL_STATE_DIRECTORY="$SYSTEMCTL_STATE_DIRECTORY" \
    "$INSTALLER"
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

@test "installer reloads and restarts before switching the GC root" {
  run invoke_installer

  [ "$status" -eq 0 ]
  cmp "$SERVICE" "$INSTALL_TARGET/nh-clean.service"
  cmp "$TIMER" "$INSTALL_TARGET/nh-clean.timer"
  cmp "$RESULT_ROOT_SERVICE" "$INSTALL_TARGET/nh-clean-result-roots.service"
  cmp "$RESULT_ROOT_TIMER" "$INSTALL_TARGET/nh-clean-result-roots.timer"
  [ -L "$INSTALL_GCROOT" ]
  [ ! -e "$INSTALL_GCROOT.next" ]
  [[ "$(readlink "$INSTALL_GCROOT")" == /nix/store/*-nh-cleanup-systemd-units ]]
  grep -Fqx 'locks=present' "$SYSTEMCTL_LOG"
  grep -Fqx 'next-root=present' "$SYSTEMCTL_LOG"
  grep -Fqx 'units=present' "$SYSTEMCTL_LOG"
  grep -Fqx 'restart-root=absent' "$SYSTEMCTL_LOG"
  ! grep -Fq 'systemctl start ' "$SYSTEMCTL_LOG"

  local reload_line enable_line restart_line
  reload_line=$(grep -nF 'systemctl daemon-reload' "$SYSTEMCTL_LOG" | cut -d: -f1)
  enable_line=$(grep -nF 'systemctl enable nh-clean.timer nh-clean-result-roots.timer' "$SYSTEMCTL_LOG" | cut -d: -f1)
  restart_line=$(grep -nF 'systemctl restart nh-clean.timer nh-clean-result-roots.timer' "$SYSTEMCTL_LOG" | cut -d: -f1)
  [ "$reload_line" -lt "$enable_line" ]
  [ "$enable_line" -lt "$restart_line" ]
}

@test "installer failure preserves the old GC root and restores quiesced timers" {
  local old_unit_tree="$BATS_TEST_TMPDIR/old-unit-tree"
  mkdir -p "$old_unit_tree" "$(dirname "$INSTALL_GCROOT")"
  ln -s "$old_unit_tree" "$INSTALL_GCROOT"
  SYSTEMCTL_FAIL_COMMAND=daemon-reload

  run invoke_installer

  [ "$status" -eq 42 ]
  [ "$(readlink "$INSTALL_GCROOT")" = "$old_unit_tree" ]
  [ -L "$INSTALL_GCROOT.next" ]
  [[ "$(readlink "$INSTALL_GCROOT.next")" == /nix/store/*-nh-cleanup-systemd-units ]]
  grep -Fqx 'systemctl start nh-clean.timer' "$SYSTEMCTL_LOG"
  grep -Fqx 'systemctl start nh-clean-result-roots.timer' "$SYSTEMCTL_LOG"
}

@test "system services serialize cleanup on the shared lock" {
  grep -Eq '^ExecStart=/nix/store/.+/bin/flock --exclusive /run/nh-cleanup-systemd/cleanup.lock ' \
    "$SERVICE"
  grep -Eq '^ExecStart=/nix/store/.+/bin/flock --exclusive /run/nh-cleanup-systemd/cleanup.lock ' \
    "$RESULT_ROOT_SERVICE"
}

@test "installer waits through every non-terminal oneshot state" {
  # shellcheck source=../_packages/cleanup-systemd/install-nh-cleanup-systemd.sh
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
  # shellcheck source=../_packages/cleanup-systemd/install-nh-cleanup-systemd.sh
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
  # shellcheck source=../_packages/cleanup-systemd/install-nh-cleanup-systemd.sh
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
