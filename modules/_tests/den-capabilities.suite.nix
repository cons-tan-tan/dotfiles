{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../..,
}:
let
  configurationTargets = import (repoRoot + "/modules/entities/_lib/configuration-targets.nix") {
    inherit lib;
  };
  targetWindows = {
    enable = true;
    username = "alice-win";
    homedir = "/mnt/c/Users/alice-win";
  };
  targetUser = {
    userName = "alice";
    dotfiles.primary = true;
  };
  targetDen = {
    hosts.x86_64-linux.wsl = {
      dotfiles = {
        environment = "wsl";
        source = "/nix/store/wsl-source";
        windows = targetWindows;
      };
      intoAttr = [
        "nixosConfigurations"
        "wsl"
      ];
      users.alice = targetUser;
    };
    homes.x86_64-linux = {
      linux = {
        userName = "alice";
        dotfiles = {
          environment = "linux";
          source = "/home/alice/source";
        };
        intoAttr = [
          "homeConfigurations"
          "alice@linux"
        ];
      };
      wsl = {
        userName = "alice";
        dotfiles = {
          environment = "wsl";
          source = "/home/alice/source";
          windows = targetWindows;
        };
        intoAttr = [
          "homeConfigurations"
          "alice@wsl"
        ];
      };
    };
  };
  resolveTargetFixture =
    den:
    configurationTargets {
      inherit den;
      system = "x86_64-linux";
    };

  projectMetadataType = lib.types.submodule {
    options = {
      managed = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      profile = lib.mkOption {
        type = lib.types.enum [
          "personal"
          "workstation"
        ];
        default = "personal";
      };
    };
  };

  projectSchema = {
    den.schema.host.options.dotfiles = lib.mkOption {
      type = projectMetadataType;
      default = { };
    };
    den.schema.user.options.dotfiles = lib.mkOption {
      type = projectMetadataType;
      default = { };
    };
    den.schema.home.options.dotfiles = lib.mkOption {
      type = projectMetadataType;
      default = { };
    };
  };

  testDefaults = {
    den.default.nixos = {
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "/dev/fake";
        fsType = "auto";
      };
    };
  };

  evalTest =
    module:
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeModules.denTest
        {
          denTest.imports = [
            inputs.den.flakeOutputs.flake
            projectSchema
            testDefaults
          ];
        }
        (
          { denTest, ... }:
          {
            options.result = lib.mkOption { type = lib.types.raw; };
            config.result = denTest module;
          }
        )
      ];
    }).config.result;

  obsidianClass =
    den: lib:
    { class, aspect-chain }:
    den.batteries.forward {
      each = lib.singleton class;
      fromClass = _: "obsidian";
      intoClass = _: "homeManager";
      intoPath = _: [
        "programs"
        "obsidian"
      ];
      fromAspect = _: lib.last aspect-chain;
      guard = { options, ... }: options ? programs.obsidian;
    };

  tests = {
    testHostScopeClassModuleEntityArgs = evalTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.desktop.cosmic.nixos =
          { user, ... }:
          {
            environment.etc."cosmic-autologin".text = user.userName;
          };
        den.aspects.igloo.includes = [ den.aspects.desktop.cosmic ];

        expr = igloo.environment.etc."cosmic-autologin".text or "<dropped>";
        expected = "tux";
      }
    );

    testStandaloneHomesHaveDistinctIdentity = evalTest (
      { den, ... }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.homes.x86_64-linux."tux@workstation" = { };

        expr =
          den.homes.x86_64-linux."tux@igloo".id_hash == den.homes.x86_64-linux."tux@workstation".id_hash;
        expected = false;
      }
    );

    testCustomForwardWithHostAspects = evalTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den.batteries.host-aspects
          (obsidianClass den lib)
        ];
        den.aspects.obsidian.obsidian.enable = true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.obsidian ];

        expr = tuxHm.programs.obsidian.enable or false;
        expected = true;
      }
    );

    testCustomForwardFromUserAspectWithHostAspects = evalTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den.batteries.host-aspects
          (obsidianClass den lib)
        ];
        den.aspects.obsidian.obsidian.enable = true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ den.aspects.obsidian ];

        expr = tuxHm.programs.obsidian.enable or false;
        expected = true;
      }
    );

    testStandaloneHomeBindsUserEntityArg = evalTest (
      { den, config, ... }:
      {
        den.default.includes = [ den.batteries.define-user ];
        den.homes.x86_64-linux.tux = { };
        den.aspects.probe.homeManager =
          { user, ... }:
          {
            home.file."OUT".text = "user=${user.name}";
          };
        den.aspects.tux.includes = [ den.aspects.probe ];

        expr = config.flake.homeConfigurations.tux.config.home.file."OUT".text or "<dropped>";
        expected = "user=tux";
      }
    );

    testSyntheticHostHomeBindsUserEntityArg = evalTest (
      { den, config, ... }:
      {
        den.default.includes = [ den.batteries.define-user ];
        den.homes.x86_64-linux."tux@astra" = { };
        den.aspects.probe.homeManager =
          { user, ... }:
          {
            home.file."OUT".text = "user=${user.name}";
          };
        den.aspects.tux.includes = [ den.aspects.probe ];

        expr = config.flake.homeConfigurations."tux@astra".config.home.file."OUT".text or "<dropped>";
        expected = "user=tux";
      }
    );

    testTypedProjectMetadataOnEveryEntity = evalTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          dotfiles.profile = "workstation";
          users.tux.dotfiles.managed = false;
        };
        den.homes.x86_64-linux.tux.dotfiles.profile = "personal";

        expr = {
          host = den.hosts.x86_64-linux.igloo.dotfiles.profile;
          user = den.hosts.x86_64-linux.igloo.users.tux.dotfiles.managed;
          home = den.homes.x86_64-linux.tux.dotfiles.profile;
        };
        expected = {
          host = "workstation";
          user = false;
          home = "personal";
        };
      }
    );
  };

  evalDen =
    module:
    lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeOutputs.flake
        inputs.den.flakeModule
        projectSchema
        module
      ];
    };
  evaluate = module: select: builtins.deepSeq (select (evalDen module).config) true;

  failureCases = {
    configurationTargetMissingEnvironment = {
      expression = resolveTargetFixture (targetDen // { homes.x86_64-linux = { }; });
      expectedFragments = [
        "standalone Linux Home Manager target requires exactly one linux entity"
        "found 0"
      ];
    };
    configurationTargetDuplicatePrimaryUser = {
      expression = resolveTargetFixture (
        targetDen
        // {
          hosts.x86_64-linux.wsl = targetDen.hosts.x86_64-linux.wsl // {
            users = targetDen.hosts.x86_64-linux.wsl.users // {
              bob = {
                userName = "bob";
                dotfiles.primary = true;
              };
            };
          };
        }
      );
      expectedFragments = [
        "NixOS-WSL configuration target wsl.users requires exactly one dotfiles.primary user"
        "found 2"
      ];
    };
    configurationTargetMissingSource = {
      expression = resolveTargetFixture (
        targetDen
        // {
          hosts.x86_64-linux.wsl = targetDen.hosts.x86_64-linux.wsl // {
            dotfiles = removeAttrs targetDen.hosts.x86_64-linux.wsl.dotfiles [ "source" ];
          };
        }
      );
      expectedFragments = [
        "NixOS-WSL configuration target wsl.dotfiles.source must be a non-empty string"
      ];
    };
    configurationTargetMissingWindowsUsername = {
      expression = resolveTargetFixture (
        targetDen
        // {
          hosts.x86_64-linux.wsl = targetDen.hosts.x86_64-linux.wsl // {
            dotfiles = targetDen.hosts.x86_64-linux.wsl.dotfiles // {
              windows = removeAttrs targetWindows [ "username" ];
            };
          };
        }
      );
      expectedFragments = [
        "NixOS-WSL configuration target wsl.dotfiles.windows.username is required"
      ];
    };
    configurationTargetWindowsPathMismatch = {
      expression = resolveTargetFixture (
        targetDen
        // {
          hosts.x86_64-linux.wsl = targetDen.hosts.x86_64-linux.wsl // {
            dotfiles = targetDen.hosts.x86_64-linux.wsl.dotfiles // {
              windows = targetWindows // {
                homedir = "/mnt/c/Users/bob";
              };
            };
          };
        }
      );
      expectedFragments = [
        "NixOS-WSL configuration target wsl.dotfiles.windows.homedir must equal /mnt/c/Users/<dotfiles.windows.username>"
      ];
    };
    hostUnknownProjectField = {
      expression = evaluate {
        den.hosts.x86_64-linux.igloo.dotfiles.unknown = true;
      } (config: config.den.hosts.x86_64-linux.igloo.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.igloo.dotfiles.unknown"
        "does not exist"
      ];
    };
    hostWrongProjectFieldType = {
      expression = evaluate {
        den.hosts.x86_64-linux.igloo.dotfiles.managed = "yes";
      } (config: config.den.hosts.x86_64-linux.igloo.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.igloo.dotfiles.managed"
        "is not of type"
      ];
    };
    userUnknownProjectField = {
      expression = evaluate {
        den.hosts.x86_64-linux.igloo.users.tux.dotfiles.unknown = true;
      } (config: config.den.hosts.x86_64-linux.igloo.users.tux.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.igloo.users.tux.dotfiles.unknown"
        "does not exist"
      ];
    };
    userWrongProjectFieldType = {
      expression = evaluate {
        den.hosts.x86_64-linux.igloo.users.tux.dotfiles.profile = 1;
      } (config: config.den.hosts.x86_64-linux.igloo.users.tux.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.igloo.users.tux.dotfiles.profile"
        "is not of type"
      ];
    };
    homeUnknownProjectField = {
      expression = evaluate {
        den.homes.x86_64-linux.tux.dotfiles.unknown = true;
      } (config: config.den.homes.x86_64-linux.tux.dotfiles);
      expectedFragments = [
        "den.homes.x86_64-linux.tux.dotfiles.unknown"
        "does not exist"
      ];
    };
    homeWrongProjectFieldType = {
      expression = evaluate {
        den.homes.x86_64-linux.tux.dotfiles.managed = 1;
      } (config: config.den.homes.x86_64-linux.tux.dotfiles);
      expectedFragments = [
        "den.homes.x86_64-linux.tux.dotfiles.managed"
        "is not of type"
      ];
    };
    strictRejectsValidAspectClassIssue632 = {
      expression =
        let
          evaluated = lib.evalModules {
            specialArgs = { inherit inputs; };
            modules = [
              inputs.den.flakeModule
              inputs.den.flakeModules.strict
              { den.aspects.probe.nixos = { }; }
            ];
          };
        in
        builtins.deepSeq evaluated.config.den.aspects.probe true;
      expectedFragments = [
        "STRICT MODE"
        ''Attempted to set the option "nixos" in "den.aspects.probe"''
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
