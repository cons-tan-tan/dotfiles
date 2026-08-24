{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  meta = {
    checkName = "windows-class-dataflow-tests";
    execution = "build";
    hestiaGroup = "configurations";
  };
  windowsRoot = repoRoot + "/modules/features/windows";
  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (repoRoot + "/modules/features/windows/class.nix")
    (repoRoot + "/modules/features/cli-tools/quirk.nix")
    (repoRoot + "/modules/features/agents/base/quirk.nix")
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
            windows = {
              enable = true;
              username = windowsUser;
              homedir = "/mnt/c/Users/${windowsUser}";
            };
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
          builtins.attrNames config.flake.homeConfigurations.${name}.config.dotfiles.windows.deployments;
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
          pingu = [ "pingu-only" ];
          tux = [ "tux-only" ];
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
                  windows.enable = true;
                };
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [
        "dotfiles.platform.windows requires username and homedir when enabled"
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
                  windows = {
                    enable = true;
                    username = "alice";
                    homedir = "/mnt/c/Users/bob";
                  };
                };
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [
        "dotfiles.platform.windows.homedir must match dotfiles.platform.windows.username below /mnt/c/Users"
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
                  windows = {
                    enable = true;
                    username = "alice";
                    homedir = "/mnt/c/Users/alice";
                  };
                };
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [
        "dotfiles.platform.windows.enable requires dotfiles.platform.environment = wsl"
      ];
    };
    disabledCompanionIdentity = {
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
              homeManager.dotfiles.platform = {
                environment = "linux";
                source = "/source/broken";
                standalone = true;
                windows = {
                  username = "alice";
                  homedir = "/mnt/c/Users/alice";
                };
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [ "disabled dotfiles.platform.windows identity must be empty" ];
    };
    emptyCompanionUsername = {
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
            ];
            den.homes.x86_64-linux.broken = { };
            den.aspects.broken = {
              includes = [ features.platform-context ];
              homeManager.dotfiles.platform = {
                environment = "wsl";
                source = "/source/broken";
                standalone = true;
                windows = {
                  enable = true;
                  username = "";
                  homedir = "/mnt/c/Users/";
                };
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [ "dotfiles.platform.windows.username must be non-empty when set" ];
    };
    emptyPlatformSource = {
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
            ];
            den.homes.x86_64-linux.broken = { };
            den.aspects.broken = {
              includes = [ features.platform-context ];
              homeManager.dotfiles.platform = {
                environment = "linux";
                source = "";
                standalone = true;
              };
            };
            expr = builtins.deepSeq config.flake.homeConfigurations.broken.activationPackage true;
          }
        )).expr;
      expectedFragments = [ "dotfiles.platform.source must be a non-empty path" ];
    };
  };
in
if caseName == null then
  {
    inherit failureCases meta tests;
  }
else
  failureCases.${caseName}.expression
