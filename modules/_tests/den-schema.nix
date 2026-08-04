{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../..,
  schemaModule,
}:
let
  evalDen =
    module:
    lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeOutputs.flake
        inputs.den.flakeModule
        schemaModule
        module
      ];
    };

  evaluate = module: select: builtins.deepSeq (select (evalDen module).config) true;

  enforceAssertions =
    assertions:
    let
      failure = lib.findFirst (assertion: !assertion.assertion) null assertions;
    in
    if failure == null then true else throw failure.message;

  validWindows = {
    enable = true;
    username = "windows-user";
    homedir = "/mnt/c/Users/windows-user";
  };

  profileFixtureArgs = {
    den.aspects.environments = {
      base = { };
      integrated-home-manager = { };
    };
    features = lib.genAttrs [
      "agent-hunk-wsl"
      "platform-darwin"
      "platform-linux"
      "platform-wsl"
      "registries-home"
      "registries-host"
      "security-gpg-darwin"
      "security-gpg-linux"
      "security-gpg-wsl"
      "source-control-ghq-sync-launchd"
      "source-control-ghq-sync-systemd"
      "trash-darwin"
      "trash-systemd"
    ] (_: { });
    inherit inputs;
  };
  environmentProfiles = {
    darwin =
      (import (repoRoot + "/modules/aspects/environments/darwin.nix") profileFixtureArgs)
      .den.aspects.environments.darwin;
    linux =
      (import (repoRoot + "/modules/aspects/environments/linux.nix") profileFixtureArgs)
      .den.aspects.environments.linux;
    wsl =
      (import (repoRoot + "/modules/aspects/environments/wsl.nix") profileFixtureArgs)
      .den.aspects.environments;
  };
  profileOwner = environment: {
    dotfiles = {
      inherit environment;
      source = "/tmp/dotfiles";
    };
  };

  tests = {
    testValidProjectMetadata = {
      expr =
        evaluate
          {
            den.hosts.aarch64-darwin.workstation = {
              dotfiles = {
                environment = "darwin";
                source = "/Users/test/dotfiles";
              };
              users.test.dotfiles = {
                primary = true;
                shell = "zsh";
              };
            };
            den.homes.x86_64-linux."test@standalone-wsl".dotfiles = {
              environment = "wsl";
              source = "/home/test/dotfiles";
              windows = validWindows;
            };
          }
          (config: {
            host = config.den.hosts.aarch64-darwin.workstation.dotfiles;
            user = config.den.hosts.aarch64-darwin.workstation.users.test.dotfiles;
            home = config.den.homes.x86_64-linux."test@standalone-wsl".dotfiles;
          });
      expected = true;
    };
    testMatchingEnvironmentProfilesAreAccepted = {
      expr = [
        (enforceAssertions
          (environmentProfiles.darwin.homeManager {
            host = profileOwner "darwin";
          }).assertions
        )
        (enforceAssertions
          (environmentProfiles.linux.homeManager {
            home = profileOwner "linux";
          }).assertions
        )
        (enforceAssertions
          (environmentProfiles.wsl.wsl.nixos {
            host = profileOwner "wsl";
          }).assertions
        )
      ];
      expected = [
        true
        true
        true
      ];
    };
  };

  failureCases = {
    hostUnknownProjectField = {
      expression = evaluate {
        den.hosts.x86_64-linux.host.dotfiles = {
          environment = "linux";
          source = "/tmp/dotfiles";
          unknown = true;
        };
      } (config: config.den.hosts.x86_64-linux.host.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.host.dotfiles.unknown"
        "does not exist"
      ];
    };
    hostWrongProjectFieldType = {
      expression = evaluate {
        den.hosts.x86_64-linux.host.dotfiles = {
          environment = "linux";
          source = 1;
        };
      } (config: config.den.hosts.x86_64-linux.host.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.host.dotfiles.source"
        "is not of type"
      ];
    };
    userUnknownProjectField = {
      expression = evaluate {
        den.hosts.x86_64-linux.host.users.test.dotfiles.unknown = true;
      } (config: config.den.hosts.x86_64-linux.host.users.test.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.host.users.test.dotfiles.unknown"
        "does not exist"
      ];
    };
    userWrongProjectFieldType = {
      expression = evaluate {
        den.hosts.x86_64-linux.host.users.test.dotfiles.primary = "yes";
      } (config: config.den.hosts.x86_64-linux.host.users.test.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.host.users.test.dotfiles.primary"
        "is not of type"
      ];
    };
    homeUnknownProjectField = {
      expression = evaluate {
        den.homes.x86_64-linux."test@standalone".dotfiles = {
          environment = "linux";
          source = "/tmp/dotfiles";
          unknown = true;
        };
      } (config: config.den.homes.x86_64-linux."test@standalone".dotfiles);
      expectedFragments = [
        "den.homes.x86_64-linux.\"test@standalone\".dotfiles.unknown"
        "does not exist"
      ];
    };
    homeWrongProjectFieldType = {
      expression = evaluate {
        den.homes.x86_64-linux."test@standalone".dotfiles = {
          environment = "linux";
          source = false;
        };
      } (config: config.den.homes.x86_64-linux."test@standalone".dotfiles);
      expectedFragments = [
        "den.homes.x86_64-linux.\"test@standalone\".dotfiles.source"
        "is not of type"
      ];
    };
    invalidEnvironment = {
      expression = evaluate {
        den.hosts.x86_64-linux.host.dotfiles = {
          environment = "freebsd";
          source = "/tmp/dotfiles";
        };
      } (config: config.den.hosts.x86_64-linux.host.dotfiles);
      expectedFragments = [
        "den.hosts.x86_64-linux.host.dotfiles.environment"
        "is not of type"
        ''one of "darwin", "linux", "wsl"''
      ];
    };
    wslHostMissingCompanion = {
      expression =
        let
          evaluated = evalDen {
            den.hosts.x86_64-linux.wsl.dotfiles = {
              environment = "wsl";
              source = "/tmp/dotfiles";
            };
          };
        in
        enforceAssertions evaluated.config.den.hosts.x86_64-linux.wsl.assertions;
      expectedFragments = [
        "dotfiles.environment = wsl requires an enabled Windows companion"
      ];
    };
    wslHomeMissingCompanion = {
      expression =
        let
          evaluated = evalDen {
            den.homes.x86_64-linux."test@standalone-wsl".dotfiles = {
              environment = "wsl";
              source = "/tmp/dotfiles";
            };
          };
        in
        enforceAssertions evaluated.config.den.homes.x86_64-linux."test@standalone-wsl".assertions;
      expectedFragments = [
        "dotfiles.environment = wsl requires an enabled Windows companion"
      ];
    };
    nonWslHostWithCompanion = {
      expression =
        let
          evaluated = evalDen {
            den.hosts.x86_64-linux.host.dotfiles = {
              environment = "linux";
              source = "/tmp/dotfiles";
              windows = validWindows;
            };
          };
        in
        enforceAssertions evaluated.config.den.hosts.x86_64-linux.host.assertions;
      expectedFragments = [ "non-WSL dotfiles.windows metadata must be disabled and empty" ];
    };
    nonWslHomeWithResidualCompanionMetadata = {
      expression =
        let
          evaluated = evalDen {
            den.homes.x86_64-linux."test@standalone-linux".dotfiles = {
              environment = "linux";
              source = "/tmp/dotfiles";
              windows = {
                username = "windows-user";
                homedir = "/mnt/c/Users/windows-user";
              };
            };
          };
        in
        enforceAssertions evaluated.config.den.homes.x86_64-linux."test@standalone-linux".assertions;
      expectedFragments = [ "non-WSL dotfiles.windows metadata must be disabled and empty" ];
    };
    darwinProfileRejectsLinuxOwner = {
      expression =
        enforceAssertions
          (environmentProfiles.darwin.homeManager {
            host = profileOwner "linux";
          }).assertions;
      expectedFragments = [
        "dotfiles darwin environment aspect requires owner.dotfiles.environment = darwin"
      ];
    };
    linuxProfileRejectsWslOwner = {
      expression =
        enforceAssertions
          (environmentProfiles.linux.homeManager {
            home = profileOwner "wsl";
          }).assertions;
      expectedFragments = [
        "dotfiles linux environment aspect requires owner.dotfiles.environment = linux"
      ];
    };
    integratedWslProfileRejectsLinuxHost = {
      expression =
        enforceAssertions
          (environmentProfiles.wsl.wsl.nixos {
            host = profileOwner "linux";
          }).assertions;
      expectedFragments = [
        "dotfiles wsl environment aspect requires owner.dotfiles.environment = wsl"
      ];
    };
    standaloneWslProfileRejectsLinuxHome = {
      expression =
        let
          outerModule = environmentProfiles.wsl.standalone-wsl.homeManager {
            home = profileOwner "linux";
          };
          profileModule = builtins.head outerModule.imports;
        in
        enforceAssertions
          (profileModule {
            config.home.homeDirectory = "/home/test";
          }).assertions;
      expectedFragments = [
        "dotfiles wsl environment aspect requires owner.dotfiles.environment = wsl"
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
