# recoverableな削除を提供し、7日経過したゴミ箱だけをagent外のtimerで掃除する。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  retentionDays = 7;
  scheduleHour = 3;
  trashEmpty = lib.getExe' pkgs.trash-cli "trash-empty";
  scheduleHourString = lib.fixedWidthString 2 "0" (toString scheduleHour);
in
lib.mkMerge [
  {
    home.packages = [ pkgs.trash-cli ];
  }

  (lib.mkIf (config.my.isLinux || config.my.isWsl) {
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
  })

  (lib.mkIf config.my.isDarwin {
    launchd.agents.trash-gc = {
      enable = true;
      domain = "user";
      config = {
        ProgramArguments = [
          trashEmpty
          (toString retentionDays)
        ];
        StartCalendarInterval = [
          {
            Hour = scheduleHour;
            Minute = 0;
          }
        ];
        Nice = 10;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/trash-gc.out.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/trash-gc.err.log";
      };
    };
  })
]
