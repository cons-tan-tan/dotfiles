{
  homeManager,
  lib,
  pkgs,
}:
let
  mkEvaluated =
    {
      platformModule,
      homeDirectory ? "/home/test",
    }:
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../_lib/common.nix
        platformModule
        {
          home = {
            username = "test";
            inherit homeDirectory;
            stateVersion = "24.11";
          };
        }
      ];
    }).config;
  trashEmpty = lib.getExe' pkgs.trash-cli "trash-empty";
  platformTest =
    predicate: test:
    if predicate then
      test
    else
      {
        expr = true;
        expected = true;
      };
  linux = mkEvaluated { platformModule = ../_lib/systemd.nix; };
  wsl = mkEvaluated { platformModule = ../_lib/systemd.nix; };
  darwin = mkEvaluated {
    platformModule = ../_lib/darwin.nix;
    homeDirectory = "/Users/test";
  };
  systemdContract =
    evaluated:
    let
      service = evaluated.systemd.user.services.trash-gc.Service;
      timer = evaluated.systemd.user.timers.trash-gc;
    in
    builtins.elem pkgs.trash-cli evaluated.home.packages
    && service.ExecStart == [ "${trashEmpty} 7" ]
    && service.Type == "oneshot"
    && timer.Timer.OnCalendar == "*-*-* 03:00:00"
    && timer.Timer.Persistent
    && timer.Install.WantedBy == [ "timers.target" ]
    && !(evaluated.launchd.agents ? trash-gc);
in
{
  testLinuxUsesRecoverableTrashWithSevenDayGc = platformTest pkgs.stdenv.hostPlatform.isLinux {
    expr = systemdContract linux;
    expected = true;
  };

  testWslUsesTheSameGcContractAsLinux = platformTest pkgs.stdenv.hostPlatform.isLinux {
    expr = systemdContract wsl && systemdContract wsl == systemdContract linux;
    expected = true;
  };

  testDarwinUsesLaunchdWithoutEnablingSystemd = platformTest pkgs.stdenv.hostPlatform.isDarwin {
    expr =
      let
        agent = darwin.launchd.agents.trash-gc;
        calendar = builtins.head agent.config.StartCalendarInterval;
      in
      builtins.elem pkgs.trash-cli darwin.home.packages
      && agent.enable
      && agent.domain == "user"
      &&
        agent.config.ProgramArguments == [
          trashEmpty
          "7"
        ]
      && calendar.Hour == 3
      && calendar.Minute == 0
      && !(darwin.systemd.user.services ? trash-gc)
      && !(darwin.systemd.user.timers ? trash-gc);
    expected = true;
  };
}
