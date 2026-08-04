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
}

@test "system service runs the shared policy as the configured user" {
  [ -x "$INSTALLER" ]
  grep -Fqx "User=constantan" "$SERVICE"
  grep -Fqx "Environment=HOME=/home/constantan" "$SERVICE"
  grep -Eq '^ExecStart=/nix/store/.+/bin/nh-clean-growth-runner check /var/lib/nix-store-growth-checker$' \
    "$SERVICE"
  grep -Fqx "StateDirectory=nix-store-growth-checker" "$SERVICE"
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
  grep -Eq '^ExecStart=/nix/store/.+/bin/nh-prune-result-roots --keep-minutes 10080$' \
    "$RESULT_ROOT_SERVICE"
  grep -Fqx "OnCalendar=Sun *-*-* 03:00:00" "$RESULT_ROOT_TIMER"
  grep -Fqx "Persistent=true" "$RESULT_ROOT_TIMER"
}

@test "installer switches the system GC root only after successful reload" {
  grep -Fq "/nix/var/nix/gcroots/nh-cleanup-systemd" "$INSTALLER"
  grep -Eq 'ln -sfnT /nix/store/.+-nh-cleanup-systemd-units "\$next_gcroot"' "$INSTALLER"
  local restart_line root_switch_line
  restart_line=$(grep -n 'systemctl restart' "$INSTALLER" | cut -d: -f1)
  root_switch_line=$(grep -n 'mv -Tf "\$next_gcroot" "\$gcroot"' "$INSTALLER" | cut -d: -f1)
  [ "$restart_line" -lt "$root_switch_line" ]
}
