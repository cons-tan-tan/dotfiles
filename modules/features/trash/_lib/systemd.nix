{ lib, pkgs, ... }:
let
  inherit (import ./policy.nix) retentionDays scheduleHour;
  trashEmpty = lib.getExe' pkgs.trash-cli "trash-empty";
  scheduleHourString = lib.fixedWidthString 2 "0" (toString scheduleHour);
in
{
  systemd.user.services.trash-gc = {
    Unit.Description = "Empty trash entries older than ${toString retentionDays} days";
    Service = {
      Type = "oneshot";
      ExecStart = "${trashEmpty} ${toString retentionDays}";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.trash-gc = {
    Unit.Description = "Daily cleanup of expired trash entries";
    Timer = {
      OnCalendar = "*-*-* ${scheduleHourString}:00:00";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
