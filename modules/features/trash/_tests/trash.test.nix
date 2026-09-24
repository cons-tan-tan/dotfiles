{
  homeManager,
  lib,
  pkgs,
}:
let
  commandPolicyInterface = import ../../agents/base/_interface/command-policy.nix;
  trashPolicy =
    (import ../command-policy.nix { inherit lib; })
    .flake.modules.homeManager.trash.dotfiles.agentCommandPolicyContributions;
  safeDeletionPolicy =
    (import ../../safe-deletion.nix {
      config = { };
      inherit lib;
    }).flake.modules.homeManager.safe-deletion.dotfiles.agentCommandPolicyContributions;
  policyEntries = trashPolicy ++ safeDeletionPolicy;
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
        (import ../home.nix).flake.modules.homeManager.trash
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
    platformModule = (import ../systemd.nix).flake.modules.homeManager.trash-systemd;
  };
  wsl = mkEvaluated {
    platformModule = (import ../systemd.nix).flake.modules.homeManager.trash-systemd;
  };
  darwin = mkEvaluated {
    platformModule = (import ../darwin.nix).flake.modules.homeManager.trash-darwin;
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
  activationContract =
    evaluated:
    let
      activation = evaluated.home.activation.trashDirectory;
      trashDirectory = "${evaluated.xdg.dataHome}/Trash";
    in
    activation.after == [ "writeBoundary" ]
    && lib.hasInfix "/bin/prepare-trash-directory" activation.data
    && lib.hasInfix "TRASH_DIRECTORY=${lib.escapeShellArg trashDirectory}" activation.data;
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

  testActivationPreparesThePlatformTrashDirectory = {
    expr = builtins.all activationContract [
      linux
      wsl
      darwin
    ];
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
