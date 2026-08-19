{
  homeManager,
  lib,
  pkgs,
}:
let
  commandPolicyInterface = import ../../agents/base/_interface/command-policy.nix;
  policyFeatures = (import ../command-policy.nix { inherit lib; }).features;
  trashPolicyFeature = policyFeatures.trash {
    config.name = "feature/trash";
  };
  safeDeletionFeatures =
    (import ../../safe-deletion.nix {
      features.trash = { };
      inherit lib;
    }).features;
  safeDeletionFeature = safeDeletionFeatures.safe-deletion {
    config.name = "feature/safe-deletion";
  };
  policyEntries = trashPolicyFeature.agent-command-policy ++ safeDeletionFeature.agent-command-policy;
  aggregatedPolicy = commandPolicyInterface.aggregate { inherit lib; } policyEntries;
  evaluatedPolicy =
    (lib.evalModules {
      modules = [ commandPolicyInterface.options ] ++ aggregatedPolicy.modules;
    }).config.agentCommandPolicy;
  compiledPolicy = commandPolicyInterface.compiler {
    inherit lib;
    inherit (evaluatedPolicy) commands shell shellfirm;
  };
  mkEvaluated =
    {
      platformModule,
      homeDirectory ? "/home/test",
    }:
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        (import ../home.nix).features.trash.homeManager
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
  linux = mkEvaluated {
    platformModule = (import ../systemd.nix).features.trash-systemd.homeManager;
  };
  wsl = mkEvaluated {
    platformModule = (import ../systemd.nix).features.trash-systemd.homeManager;
  };
  darwin = mkEvaluated {
    platformModule = (import ../darwin.nix).features.trash-darwin.homeManager;
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
    && service.IOSchedulingClass == "idle"
    && service.Nice == 10
    && timer.Timer.OnCalendar == "*-*-* 03:00:00"
    && timer.Timer.Persistent
    && timer.Timer.RandomizedDelaySec == "30min"
    && timer.Install.WantedBy == [ "timers.target" ]
    && !(evaluated.launchd.agents ? trash-gc);
in
{
  testFeatureOwnedPolicyPreservesRecoverableDeletionBoundary = {
    expr = {
      owners = aggregatedPolicy.owners;
      exactDenied = map (rule: rule.argvPrefix) compiledPolicy.guardPolicy.exact;
      semanticCommands = map (rule: rule.commandPrefix) compiledPolicy.guardPolicy.semantic;
      nativeTrash =
        lib.all (prefix: lib.elem prefix (map (rule: rule.argvPrefix) compiledPolicy.prefixRules))
          [
            [ "trash" ]
            [ "trash-list" ]
            [ "trash-put" ]
            [ "trash-restore" ]
          ];
    };
    expected = {
      owners = [
        "feature/trash"
        "feature/safe-deletion"
      ];
      exactDenied = [
        [ "trash-empty" ]
        [ "trash-rm" ]
      ];
      semanticCommands = [
        [ "rm" ]
        [ "trash-restore" ]
      ];
      nativeTrash = true;
    };
  };

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
      && agent.config.Nice == 10
      && agent.config.ProcessType == "Background"
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
