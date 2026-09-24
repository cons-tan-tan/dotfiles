{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  mkHome = import ../../checks/_lib/eval/home-fixture.nix { inherit inputs lib repoRoot; };
  platform = {
    environment = "linux";
    source = "/source/test";
    standalone = true;
  };
  companion = name: {
    enable = true;
    username = name;
    homedir = "/mnt/c/Users/${name}";
  };
  homeFor =
    metadata: extraModules:
    mkHome {
      files = [
        "platform/context.nix"
        "windows/options.nix"
        "windows/base.nix"
        "cli-tools/options.nix"
      ];
      modules =
        hm:
        [
          hm.platform-context
          hm.home-base
          hm.windows-base
          hm.cli-tools-consumer
          {
            home.username = "shared";
            dotfiles.platform = platform // metadata;
          }
        ]
        ++ extraModules;
    };
  deployment = name: { config, lib, ... }: {
    config = lib.mkIf config.dotfiles.platform.windows.enable {
      dotfiles.windows.deployments.${name}.directories = [ ".config/${name}" ];
    };
  };
  describe =
    metadata: name:
    builtins.attrNames (homeFor metadata [ (deployment name) ]).config.dotfiles.windows.deployments;
  failsWith = metadata: message: {
    expression = builtins.seq (homeFor metadata [ ]).activationPackage.drvPath true;
    expectedFragments = [ message ];
  };
  failureCases = {
    missingCompanionMetadata = failsWith {
      environment = "wsl";
      windows.enable = true;
    } "dotfiles.platform.windows requires username and homedir when enabled";
    missingWslCompanion = failsWith {
      environment = "wsl";
    } "dotfiles.platform.environment = wsl requires an enabled Windows companion";
    mismatchedCompanionHome =
      failsWith
        {
          environment = "wsl";
          windows = (companion "alice") // {
            homedir = "/mnt/c/Users/bob";
          };
        }
        "dotfiles.platform.windows.homedir must match dotfiles.platform.windows.username below /mnt/c/Users";
    mismatchedCompanionEnvironment = failsWith {
      windows = companion "alice";
    } "dotfiles.platform.windows.enable requires dotfiles.platform.environment = wsl";
    disabledCompanionIdentity = failsWith {
      windows = (companion "alice") // {
        enable = false;
      };
    } "disabled dotfiles.platform.windows identity must be empty";
    emptyCompanionUsername = failsWith {
      environment = "wsl";
      windows = companion "";
    } "dotfiles.platform.windows.username must be non-empty when set";
    emptyPlatformSource = failsWith {
      source = "";
    } "dotfiles.platform.source must be a non-empty path";
  };
in
if caseName != null then
  failureCases.${caseName}.expression
else
  {
    meta = {
      checkName = "windows-dataflow-tests";
      execution = "build";
      hestiaGroup = "configurations";
    };
    tests.testCompanionsWithSameLinuxUserStayIsolated = {
      expr = {
        linux = describe { } "must-not-leak";
        pingu = describe {
          environment = "wsl";
          windows = companion "pingu-win";
        } "pingu-only";
        tux = describe {
          environment = "wsl";
          windows = companion "tux-win";
        } "tux-only";
      };
      expected = {
        linux = [ ];
        pingu = [ "pingu-only" ];
        tux = [ "tux-only" ];
      };
    };
    inherit failureCases;
  }
