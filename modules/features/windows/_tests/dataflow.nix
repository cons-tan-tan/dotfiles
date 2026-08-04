{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  windowsRoot = repoRoot + "/modules/features/windows";
  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (repoRoot + "/modules/classes/windows.nix")
    (repoRoot + "/modules/quirks/cli-tools.nix")
  ];

  evalTest =
    module:
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeModules.denTest
        { denTest.imports = testImports; }
        (
          { denTest, ... }:
          {
            options.result = lib.mkOption { type = lib.types.raw; };
            config.result = denTest module;
          }
        )
      ];
    }).config.result;

  baseHome =
    { lib, ... }:
    {
      den.default.homeManager.home = {
        username = lib.mkDefault "test";
        homeDirectory = lib.mkDefault "/home/test";
        stateVersion = "25.11";
      };
    };

  mkCompanionAspect =
    {
      deployment,
      features,
      linuxUser,
      windowsUser,
    }:
    {
      includes = [
        features.platform-context
        features.windows-base
      ];
      homeManager = {
        home = {
          username = lib.mkForce linuxUser;
          homeDirectory = lib.mkForce "/home/${linuxUser}";
        };
        dotfiles = {
          platform = {
            environment = "wsl";
            source = "/source/${linuxUser}";
            standalone = true;
            windowsCompanion = true;
            nhCleanupOwner = "switch-app";
          };
          windows = {
            enable = true;
            environment = "wsl";
            username = windowsUser;
            homedir = "/mnt/c/Users/${windowsUser}";
            linuxHomedir = "/home/${linuxUser}";
            source = "/source/${linuxUser}";
          };
        };
      };
      windows.dotfiles.windows.deployments.${deployment}.directories = [ ".config/${deployment}" ];
    };

  tests = {
    testGuardedForwardKeepsSameClassHomesIsolated = evalTest (
      {
        config,
        features,
        ...
      }:
      let
        describe =
          name:
          let
            home = config.flake.homeConfigurations.${name}.config;
          in
          {
            inherit (home.dotfiles.windows)
              homedir
              linuxHomedir
              source
              username
              ;
            deployments = builtins.attrNames home.dotfiles.windows.deployments;
          };
      in
      {
        imports = [
          baseHome
          (repoRoot + "/modules/features/platform/context.nix")
          (windowsRoot + "/base.nix")
        ];
        den.homes.x86_64-linux = {
          linux = { };
          pingu = { };
          tux = { };
        };
        den.aspects.linux = {
          includes = [
            features.platform-context
            features.windows-base
          ];
          homeManager.dotfiles.platform = {
            environment = "linux";
            source = "/source/linux";
            standalone = true;
            windowsCompanion = false;
            nhCleanupOwner = "home-manager";
          };
          windows.dotfiles.windows.deployments.must-not-leak.directories = [ ".config/leaked" ];
        };
        den.aspects.pingu = mkCompanionAspect {
          deployment = "pingu-only";
          inherit features;
          linuxUser = "shared";
          windowsUser = "pingu-win";
        };
        den.aspects.tux = mkCompanionAspect {
          deployment = "tux-only";
          inherit features;
          linuxUser = "shared";
          windowsUser = "tux-win";
        };

        expr = {
          linuxDeployments = builtins.attrNames config.flake.homeConfigurations.linux.config.dotfiles.windows.deployments;
          pingu = describe "pingu";
          tux = describe "tux";
        };
        expected = {
          linuxDeployments = [ ];
          pingu = {
            deployments = [ "pingu-only" ];
            homedir = "/mnt/c/Users/pingu-win";
            linuxHomedir = "/home/shared";
            source = "/source/shared";
            username = "pingu-win";
          };
          tux = {
            deployments = [ "tux-only" ];
            homedir = "/mnt/c/Users/tux-win";
            linuxHomedir = "/home/shared";
            source = "/source/shared";
            username = "tux-win";
          };
        };
      }
    );
  };

  failureCases = {
    missingCompanionMetadata = {
      expression =
        (evalTest (
          {
            config,
            features,
            ...
          }:
          {
            imports = [
              baseHome
              (repoRoot + "/modules/features/platform/context.nix")
              (windowsRoot + "/base.nix")
            ];
            den.homes.x86_64-linux.broken = { };
            den.aspects.broken = {
              includes = [
                features.platform-context
                features.windows-base
              ];
              homeManager = {
                dotfiles.platform = {
                  environment = "wsl";
                  source = "/source/broken";
                  standalone = true;
                  windowsCompanion = true;
                  nhCleanupOwner = "switch-app";
                };
                dotfiles.windows.enable = true;
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [
        "dotfiles.windows requires WSL environment, username, homedir, linuxHomedir, and source metadata"
      ];
    };
    mismatchedCompanionHome = {
      expression =
        (evalTest (
          {
            config,
            features,
            ...
          }:
          {
            imports = [
              baseHome
              (repoRoot + "/modules/features/platform/context.nix")
              (windowsRoot + "/base.nix")
            ];
            den.homes.x86_64-linux.broken = { };
            den.aspects.broken = {
              includes = [
                features.platform-context
                features.windows-base
              ];
              homeManager.dotfiles = {
                platform = {
                  environment = "wsl";
                  source = "/source/broken";
                  standalone = true;
                  windowsCompanion = true;
                  nhCleanupOwner = "switch-app";
                };
                windows = {
                  enable = true;
                  environment = "wsl";
                  username = "alice";
                  homedir = "/mnt/c/Users/bob";
                  linuxHomedir = "/home/test";
                  source = "/source/broken";
                };
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [
        "dotfiles.windows.homedir must match dotfiles.windows.username below /mnt/c/Users"
      ];
    };
    mismatchedCompanionEnvironment = {
      expression =
        (evalTest (
          {
            config,
            features,
            ...
          }:
          {
            imports = [
              baseHome
              (repoRoot + "/modules/features/platform/context.nix")
              (windowsRoot + "/base.nix")
            ];
            den.homes.x86_64-linux.broken = { };
            den.aspects.broken = {
              includes = [
                features.platform-context
                features.windows-base
              ];
              homeManager.dotfiles = {
                platform = {
                  environment = "linux";
                  source = "/source/broken";
                  standalone = true;
                  windowsCompanion = true;
                  nhCleanupOwner = "home-manager";
                };
                windows = {
                  enable = true;
                  environment = "wsl";
                  username = "alice";
                  homedir = "/mnt/c/Users/alice";
                  linuxHomedir = "/home/test";
                  source = "/source/broken";
                };
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [
        "dotfiles.windows.environment must match dotfiles.platform.environment"
      ];
    };
  };
in
if caseName == null then
  {
    inherit failureCases tests;
  }
else
  failureCases.${caseName}.expression
