let
  inherit (import ./_data/policy.nix) retentionDays scheduleHour;
in
{
  flake.modules.homeManager.trash-systemd =
    { lib, pkgs, ... }:
    let
      trashEmpty = lib.getExe' pkgs.trash-cli "trash-empty";
      scheduleHourString = lib.fixedWidthString 2 "0" (toString scheduleHour);
    in
    {
      key = "modules/features/trash/systemd.nix#homeManager.trash-systemd";

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
    };
}
