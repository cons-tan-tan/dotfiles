{
  flake,
  inputs,
  lib,
  pkgs,
  username,
}:
let
  systems = import inputs.supported-systems;
  validateScriptEntries = import ./validate-script-entries.nix { inherit lib; };
  mkEntry = name: {
    inherit name;
    mkDerivation =
      { pkgs, system, ... }:
      pkgs.writeText "${name}-${system}" system;
  };
  mkFixture =
    producerModule:
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
          ../../../modules/flake/den-output-routing.nix
          ../../../modules/flake/systems.nix
          ../../../modules/features/nixpkgs.nix
          ../../../modules/features/apps/scripts.nix
        ];

        den.schema.flake-parts.includes = [
          den.aspects.first-script-producer
          den.aspects.second-script-producer
        ];

        den.aspects.first-script-producer = producerModule.first;
        den.aspects.second-script-producer = producerModule.second;

        flake.quirkScripts = lib.genAttrs systems (
          system: withSystem system ({ config, ... }: config.dotfiles.appScripts)
        );
      }
    );
  fixture = mkFixture {
    first.app-scripts = [ (mkEntry "alpha") ];
    second.app-scripts = [ (mkEntry "beta") ];
  };
  invalidFixture = mkFixture {
    first.app-scripts = [ { name = "missing-builder"; } ];
    second.app-scripts = [ (mkEntry "valid") ];
  };
  duplicateEntries = [
    (mkEntry "duplicate")
    (mkEntry "duplicate")
  ];
  expectedCommonApps = (import ./mk-common-apps.nix { inherit inputs username; }) {
    inherit pkgs;
    treefmtWrapper = flake.formatter.${pkgs.stdenv.hostPlatform.system};
  };
  expectedPrograms = lib.mapAttrs (_: app: app.program) expectedCommonApps.apps;
  actualPrograms = lib.mapAttrs (
    name: _: flake.apps.${pkgs.stdenv.hostPlatform.system}.${name}.program
  ) expectedCommonApps.apps;
in
{
  testTwoProducersMergeIntoOneConsumer = {
    expr = lib.sort builtins.lessThan (map lib.getName fixture.quirkScripts.x86_64-linux);
    expected = [
      "alpha-x86_64-linux"
      "beta-x86_64-linux"
    ];
  };

  testInvalidQuirkPayloadRejected = {
    expr = (builtins.tryEval (builtins.deepSeq invalidFixture.quirkScripts.x86_64-linux null)).success;
    expected = false;
  };

  testDuplicateScriptNamesRejected = {
    expr = (builtins.tryEval (builtins.deepSeq (validateScriptEntries duplicateEntries) null)).success;
    expected = false;
  };

  testScriptDerivationsStaySystemSeparated = {
    expr = {
      aarch64LinuxSystem = (builtins.head fixture.quirkScripts.aarch64-linux).system;
      x86LinuxSystem = (builtins.head fixture.quirkScripts.x86_64-linux).system;
      drvPathsDiffer =
        (builtins.head fixture.quirkScripts.aarch64-linux).drvPath
        != (builtins.head fixture.quirkScripts.x86_64-linux).drvPath;
    };
    expected = {
      aarch64LinuxSystem = "aarch64-linux";
      x86LinuxSystem = "x86_64-linux";
      drvPathsDiffer = true;
    };
  };

  testPublicCommonAppsKeepLeafBuilderPrograms = {
    expr = actualPrograms;
    expected = expectedPrograms;
  };
}
