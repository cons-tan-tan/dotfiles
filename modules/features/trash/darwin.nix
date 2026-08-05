{ ... }:
let
  inherit (import ./_data/policy.nix) retentionDays scheduleHour;
in
{
  features.trash-darwin.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      trashEmpty = lib.getExe' pkgs.trash-cli "trash-empty";
    in
    {
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
    };
}
