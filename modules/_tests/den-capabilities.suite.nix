{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../..,
}:
let
  meta = builtins.seq repoRoot {
    checkName = "den-capability-tests";
    execution = "build";
    hestiaGroup = "eval-tests";
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
  evaluateNixosOutput =
    module:
    builtins.deepSeq ((lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeOutputs.nixosConfigurations
        inputs.den.flakeModule
        module
      ];
    }).config.flake.nixosConfigurations.collision.config.warnings
    ) true;

  failureCases = {
    classModuleArgsRejectCollisions = {
      expression = evaluateNixosOutput (
        { den, ... }:
        {
          den.aspects.arg-collision = {
            name = "class-module-arg-collision";
            nixos.imports = [
              { _module.args.host = "from-module-system"; }
              (
                { host, ... }:
                {
                  networking.hostName = host.name;
                }
              )
            ];
          };
          den.hosts.x86_64-linux.collision.aspect = den.aspects.arg-collision;
        }
      );
      expectedFragments = [
        "class module arg 'host' collides with module-system arg"
        "set collisionPolicy to resolve"
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
    inherit failureCases meta tests;
  }
else
  failureCases.${caseName}.expression
