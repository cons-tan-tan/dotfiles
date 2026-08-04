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
    (repoRoot + "/modules/classes/agent-command-policy.nix")
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
            windows = {
              enable = true;
              username = windowsUser;
              homedir = "/mnt/c/Users/${windowsUser}";
            };
            nhCleanupOwner = "switch-app";
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
          nhCleanupOwner = "switch-app";
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
        overlayPlan = import (repoRoot + "/nix/lib/mk-overlays.nix") { inherit inputs; } "x86_64-linux";
        claudePkgs = config.flake.homeConfigurations.claude.pkgs;
        claudeSettingsLib = import (repoRoot + "/modules/features/agents/_lib/settings/claude.nix") {
          inherit lib;
        };
        claudeSettingsValidator =
          import (repoRoot + "/modules/features/agents/_lib/settings/claude-validator.nix")
            {
              pkgs = claudePkgs;
            };
        expectedClaudeSettingsRaw = (claudePkgs.formats.json { }).generate "claude-windows-settings.json" (
          claudeSettingsLib.mkSettings { forWindows = true; }
        );
        expectedClaudeSource = toString (
          claudeSettingsValidator.validate "claude-windows-settings.json" expectedClaudeSettingsRaw
        );
        gitPkgs = config.flake.homeConfigurations.git.pkgs;
        gitLib = import (repoRoot + "/modules/features/source-control/_lib/git.nix") {
          inherit lib;
          pkgs = gitPkgs;
        };
        expectedGitConfig = gitLib.mkSettings {
          forWindows = true;
          windowsUsername = "git-win";
        };
        expectedGitIni = gitPkgs.writeText "windows-gitconfig" (
          lib.generators.toGitINI (
            expectedGitConfig
            // {
              user = expectedGitConfig.user // {
                signingkey = gitLib.signingKey;
              };
              commit = expectedGitConfig.commit // {
                gpgsign = true;
              };
              tag.gpgsign = true;
              gpg = expectedGitConfig.gpg // {
                format = "openpgp";
              };
            }
          )
        );
        expectedGitIgnore = gitPkgs.writeText "windows-gitignore-global" (
          lib.concatStringsSep "\n" gitLib.ignores
        );
        gpgPkgs = config.flake.homeConfigurations.gpg.pkgs;
        expectedGpgAgent = gpgPkgs.writeText "windows-gpg-agent.conf" ''
          default-cache-ttl 43200
          max-cache-ttl 43200
          enable-ssh-support
          pinentry-program C:/Program Files/Gpg4win/bin/pinentry.exe
        '';
        expectedGpgConfig = gpgPkgs.writeText "windows-gpg.conf" ''
          use-agent
        '';
        expectedSshcontrol = gpgPkgs.writeText "windows-sshcontrol" (
          lib.concatStringsSep "\n" [ "60DE257CE1919B3D6DCF4E6E239CD1FFE63B45FD" ]
        );
        describe =
          name:
          let
            deployments = config.flake.homeConfigurations.${name}.config.dotfiles.windows.deployments;
            deployment = deployments.${name};
          in
          {
            keys = builtins.attrNames deployments;
            inherit (deployment) directories;
            destinations = map (file: file.destination) deployment.files;
            sources = map (file: file.source) deployment.files;
          };
      in
      {
        imports = [
          baseHome
          (repoRoot + "/modules/features/platform/context.nix")
          (windowsRoot + "/base.nix")
          (repoRoot + "/modules/features/agents/base.nix")
          (repoRoot + "/modules/features/agents/herdr.nix")
          (repoRoot + "/modules/features/agents/claude.nix")
          (repoRoot + "/modules/features/source-control/git.nix")
          (repoRoot + "/modules/features/security/gpg.nix")
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
          canonicalFeature = features.source-control-git;
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
        };
        expected = {
          claude = {
            keys = [ "claude" ];
            directories = [ ".claude" ];
            destinations = [ ".claude/settings.json" ];
            sources = [ expectedClaudeSource ];
          };
          git = {
            keys = [ "git" ];
            directories = [
              ".gitconfig.d"
              ".config/git"
            ];
            destinations = [
              ".gitconfig"
              ".gitconfig.d/commit-template"
              ".config/git/ignore"
            ];
            sources = [
              (toString expectedGitIni)
              (toString gitLib.commitTemplate)
              (toString expectedGitIgnore)
            ];
          };
          gpg = {
            keys = [ "gpg" ];
            directories = [ "AppData/Roaming/gnupg" ];
            destinations = [
              "AppData/Roaming/gnupg/gpg-agent.conf"
              "AppData/Roaming/gnupg/gpg.conf"
              "AppData/Roaming/gnupg/sshcontrol"
            ];
            sources = [
              (toString expectedGpgAgent)
              (toString expectedGpgConfig)
              (toString expectedSshcontrol)
            ];
          };
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
                  nhCleanupOwner = "switch-app";
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
                  nhCleanupOwner = "switch-app";
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
                  nhCleanupOwner = "home-manager";
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
                nhCleanupOwner = "home-manager";
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
                nhCleanupOwner = "switch-app";
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
                nhCleanupOwner = "home-manager";
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
    inherit failureCases tests;
  }
else
  failureCases.${caseName}.expression
