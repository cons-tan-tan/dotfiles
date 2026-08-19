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

  mkCanonicalCompanionAspect =
    {
      canonicalFeature,
      features,
      linuxUser,
      windowsUser,
    }:
    {
      includes = [
        features.platform-context
        features.windows-base
        canonicalFeature
      ];
      homeManager = {
        home = {
          username = lib.mkForce linuxUser;
          homeDirectory = lib.mkForce "/home/${linuxUser}";
        };
        dotfiles.platform = {
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

  tests = {
    testCanonicalFeaturesDeliverOwnWindowsContribution = evalTest (
      {
        config,
        features,
        ...
      }:
      let
        overlayPlan = (import (repoRoot + "/modules/features/nixpkgs/_interface")).mkOverlayPlan {
          inherit inputs;
          system = "x86_64-linux";
        };
        gitPkgs = config.flake.homeConfigurations.git.pkgs;
        gitLib = import (repoRoot + "/modules/features/git/_interface/git.nix") {
          inherit lib;
          pkgs = gitPkgs;
        };
        windowsGitSettings = gitLib.mkSettings {
          forWindows = true;
          windowsUsername = "git-win";
        };
        expectedGitSettingsSource = gitPkgs.writeText "windows-gitconfig" (
          lib.generators.toGitINI (
            windowsGitSettings
            // {
              user = windowsGitSettings.user // {
                signingkey = gitLib.signingKey;
              };
              commit = windowsGitSettings.commit // {
                gpgsign = true;
              };
              tag.gpgsign = true;
              gpg = windowsGitSettings.gpg // {
                format = "openpgp";
              };
            }
          )
        );
        describe =
          name:
          let
            deployments = config.flake.homeConfigurations.${name}.config.dotfiles.windows.deployments;
            deployment = deployments.${name};
          in
          {
            keys = builtins.attrNames deployments;
            hasDirectories = deployment.directories != [ ];
            hasFiles = deployment.files != [ ];
          };
        gitSettingsSource =
          let
            files = config.flake.homeConfigurations.git.config.dotfiles.windows.deployments.git.files;
            file = lib.findFirst (candidate: candidate.destination == ".gitconfig") null files;
          in
          if file == null then null else file.source;
      in
      {
        imports = [
          baseHome
          (repoRoot + "/modules/features/platform/context.nix")
          (windowsRoot + "/base.nix")
          (repoRoot + "/modules/features/agents/base/default.nix")
          (repoRoot + "/modules/features/agents/hcom/contract.nix")
          (repoRoot + "/modules/features/agents/herdr/default.nix")
          (repoRoot + "/modules/features/agents/herdr/home.nix")
          (repoRoot + "/modules/features/agents/claude/default.nix")
          (repoRoot + "/modules/features/agents/claude/home.nix")
          (repoRoot + "/modules/features/git/default.nix")
          (repoRoot + "/modules/features/security/gpg/default.nix")
        ];
        den.default.homeManager.nixpkgs.overlays = overlayPlan.overlays;
        den.homes.x86_64-linux = {
          claude = { };
          git = { };
          gpg = { };
        };
        den.aspects.claude = mkCanonicalCompanionAspect {
          canonicalFeature = features.agent-claude;
          inherit features;
          linuxUser = "claude";
          windowsUser = "claude-win";
        };
        den.aspects.git = mkCanonicalCompanionAspect {
          canonicalFeature = features.git;
          inherit features;
          linuxUser = "git";
          windowsUser = "git-win";
        };
        den.aspects.gpg = mkCanonicalCompanionAspect {
          canonicalFeature = features.security-gpg;
          inherit features;
          linuxUser = "gpg";
          windowsUser = "gpg-win";
        };

        expr = {
          claude = describe "claude";
          git = describe "git";
          gpg = describe "gpg";
          inherit gitSettingsSource;
        };
        expected = {
          claude = {
            keys = [ "claude" ];
            hasDirectories = true;
            hasFiles = true;
          };
          git = {
            keys = [ "git" ];
            hasDirectories = true;
            hasFiles = true;
          };
          gpg = {
            keys = [ "gpg" ];
            hasDirectories = true;
            hasFiles = true;
          };
          gitSettingsSource = toString expectedGitSettingsSource;
        };
      }
    );

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
            inherit (home.dotfiles.platform.windows)
              homedir
              username
              ;
            linuxHomedir = home.home.homeDirectory;
            source = home.dotfiles.platform.source;
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
            linuxHomedir = builtins.concatStringsSep "" [
              "/home/"
              "shared"
            ];
            source = "/source/shared";
            username = "pingu-win";
          };
          tux = {
            deployments = [ "tux-only" ];
            homedir = "/mnt/c/Users/tux-win";
            linuxHomedir = builtins.concatStringsSep "" [
              "/home/"
              "shared"
            ];
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
