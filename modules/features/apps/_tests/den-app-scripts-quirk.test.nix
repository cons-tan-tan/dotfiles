{
  den,
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  expectedUsername = "constantan";
  system = pkgs.stdenv.hostPlatform.system;
  systems = import inputs.supported-systems;
  mkProducer =
    names:
    {
      pkgs,
      self',
      system,
      ...
    }:
    builtins.seq (builtins.attrNames self') (
      lib.genAttrs names (name: pkgs.writeText "${name}-${system}" system)
    );
  mkProducerRecord = names: { produce = mkProducer names; };
  mkFixture =
    {
      appNamesForSystem,
      producerModule,
    }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      {
        den,
        lib,
        withSystem,
        ...
      }:
      {
        imports = [
          inputs.den.flakeModule
          ../../../flake/den-output-routing.nix
          ../../../flake/systems.nix
          ../../nixpkgs.nix
          ../scripts.nix
        ];

        den.schema.flake-parts.includes = [
          den.aspects.fixture-app-producer
          den.aspects.first-validation-producer
          den.aspects.second-validation-producer
        ];

        den.aspects.fixture-app-producer.apps =
          { system, ... }:
          lib.genAttrs (appNamesForSystem system) (name: {
            type = "app";
            meta.description = "${name} validation fixture";
            program = "/bin/true";
          });
        den.aspects.first-validation-producer = producerModule.first;
        den.aspects.second-validation-producer = producerModule.second;

        flake.quirkValidations = lib.genAttrs systems (
          system: withSystem system ({ config, ... }: config.dotfiles.appValidations)
        );
      }
    );
  mergeFixture = mkFixture {
    appNamesForSystem = _: [
      "alpha"
      "beta"
    ];
    producerModule = {
      first.app-validations = [ (mkProducerRecord [ "alpha" ]) ];
      second.app-validations = [ (mkProducerRecord [ "beta" ]) ];
    };
  };
  isolationFixture = mkFixture {
    appNamesForSystem =
      system:
      lib.optional (system == "x86_64-linux") "x86-only"
      ++ lib.optional (system == "aarch64-linux") "aarch64-only";
    producerModule = {
      first.app-validations = [
        {
          produce =
            args@{ system, ... }: (mkProducer (lib.optional (system == "x86_64-linux") "x86-only")) args;
        }
      ];
      second.app-validations = [
        {
          produce =
            args@{ system, ... }: (mkProducer (lib.optional (system == "aarch64-linux") "aarch64-only")) args;
        }
      ];
    };
  };
  invalidProducerFixture = mkFixture {
    appNamesForSystem = _: [ "valid" ];
    producerModule = {
      first.app-validations = [ { } ];
      second.app-validations = [ (mkProducerRecord [ "valid" ]) ];
    };
  };
  invalidProduceFixture = mkFixture {
    appNamesForSystem = _: [ ];
    producerModule = {
      first.app-validations = [ { produce = "not-a-function"; } ];
      second.app-validations = [ (mkProducerRecord [ ]) ];
    };
  };
  invalidResultFixture = mkFixture {
    appNamesForSystem = _: [ ];
    producerModule = {
      first.app-validations = [ { produce = _: [ ]; } ];
      second.app-validations = [ (mkProducerRecord [ ]) ];
    };
  };
  invalidPackageFixture = mkFixture {
    appNamesForSystem = _: [ "invalid" ];
    producerModule = {
      first.app-validations = [ { produce = _: { invalid = "not-a-derivation"; }; } ];
      second.app-validations = [ (mkProducerRecord [ ]) ];
    };
  };
  duplicateFixture = mkFixture {
    appNamesForSystem = _: [ "duplicate" ];
    producerModule = {
      first.app-validations = [ (mkProducerRecord [ "duplicate" ]) ];
      second.app-validations = [ (mkProducerRecord [ "duplicate" ]) ];
    };
  };
  missingValidationFixture = mkFixture {
    appNamesForSystem = _: [ "orphan" ];
    producerModule = {
      first.app-validations = [ (mkProducerRecord [ ]) ];
      second.app-validations = [ (mkProducerRecord [ ]) ];
    };
  };
  expectedCommonApps =
    (import ../../../../nix/lib/apps/mk-common-apps.nix {
      inherit inputs;
      username = expectedUsername;
    })
      {
        inherit pkgs;
        treefmtWrapper = flake.formatter.${system};
      };
  targets = (import ../../../entities/_lib/configuration-targets.nix { inherit lib; }) {
    inherit den system;
  };
  expectedHostApps =
    if pkgs.stdenv.hostPlatform.isDarwin then
      (import ../../../../nix/lib/apps/mk-darwin-apps.nix { darwinHostname = targets.darwin; }) {
        inherit pkgs;
        darwinRebuildBin = "${
          flake.darwinConfigurations.${targets.darwin}.config.system.build.darwin-rebuild
        }/bin/darwin-rebuild";
      }
    else
      (import ../../../../nix/lib/apps/mk-linux-apps.nix {
        inherit inputs;
        username = expectedUsername;
        homedir = "/home/${expectedUsername}";
        windowsHomedir = "/mnt/c/Users/zhouc";
      })
        {
          inherit pkgs system;
          homeTargets = targets.home;
          nixosTarget = targets.nixosWsl;
          nixosRebuildBin = "${
            flake.nixosConfigurations.${targets.nixosWsl}.config.system.build.nixos-rebuild
          }/bin/nixos-rebuild";
        };
  expectedPrograms = lib.mapAttrs (_: app: app.program) expectedCommonApps.apps;
  actualPrograms = lib.mapAttrs (
    name: _: flake.apps.${system}.${name}.program
  ) expectedCommonApps.apps;
  expectedValidationPaths = lib.sort builtins.lessThan (
    map toString (expectedCommonApps.validations ++ expectedHostApps.validations)
  );
  actualValidationPaths = lib.sort builtins.lessThan (
    map toString flake.checks.${system}.app-scripts.paths
  );
  expectedValidationNames = builtins.attrNames (expectedCommonApps.apps // expectedHostApps.apps);
in
{
  testTwoProducersMergeIntoOneConsumer = {
    expr = map lib.getName (builtins.attrValues mergeFixture.quirkValidations.x86_64-linux);
    expected = [
      "alpha-x86_64-linux"
      "beta-x86_64-linux"
    ];
  };

  testProducerRecordWithoutProduceIsRejected = {
    expr =
      (builtins.tryEval (builtins.deepSeq invalidProducerFixture.quirkValidations.x86_64-linux null))
      .success;
    expected = false;
  };

  testNonFunctionProduceFieldIsRejected = {
    expr =
      (builtins.tryEval (builtins.deepSeq invalidProduceFixture.quirkValidations.x86_64-linux null))
      .success;
    expected = false;
  };

  testNonAttributeSetProducerResultIsRejected = {
    expr =
      (builtins.tryEval (builtins.deepSeq invalidResultFixture.quirkValidations.x86_64-linux null))
      .success;
    expected = false;
  };

  testNonDerivationProducerValueIsRejected = {
    expr =
      (builtins.tryEval (builtins.deepSeq invalidPackageFixture.quirkValidations.x86_64-linux null))
      .success;
    expected = false;
  };

  testDuplicateValidationNamesRejected = {
    expr =
      (builtins.tryEval (builtins.deepSeq duplicateFixture.quirkValidations.x86_64-linux null)).success;
    expected = false;
  };

  testPublicAppWithoutValidationIsRejectedByFinalGate = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq missingValidationFixture.checks.x86_64-linux.app-scripts.drvPath null
      )).success;
    expected = false;
  };

  testSystemSpecificContributionsStayIsolated = {
    expr = {
      aarch64LinuxNames = map lib.getName (
        builtins.attrValues isolationFixture.quirkValidations.aarch64-linux
      );
      aarch64LinuxSystem = isolationFixture.quirkValidations.aarch64-linux.aarch64-only.system;
      x86LinuxNames = map lib.getName (
        builtins.attrValues isolationFixture.quirkValidations.x86_64-linux
      );
      x86LinuxSystem = isolationFixture.quirkValidations.x86_64-linux.x86-only.system;
    };
    expected = {
      aarch64LinuxNames = [ "aarch64-only-aarch64-linux" ];
      aarch64LinuxSystem = "aarch64-linux";
      x86LinuxNames = [ "x86-only-x86_64-linux" ];
      x86LinuxSystem = "x86_64-linux";
    };
  };

  testLiveAppGateContainsEveryValidation = {
    expr = actualValidationPaths;
    expected = expectedValidationPaths;
  };

  testLivePublicAppsAndValidationsHaveExactNames = {
    expr = flake.checks.${system}.app-scripts.validationNames;
    expected = expectedValidationNames;
  };

  testPublicCommonAppsKeepLeafBuilderPrograms = {
    expr = actualPrograms;
    expected = expectedPrograms;
  };
}
