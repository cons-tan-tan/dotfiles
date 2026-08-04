{
  flake,
  inputs,
  lib,
  pkgs,
  username,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  systems = import inputs.supported-systems;
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
  mergeFixture = mkFixture {
    first.app-scripts = [ (mkEntry "alpha") ];
    second.app-scripts = [ (mkEntry "beta") ];
  };
  isolationFixture = mkFixture {
    first.app-scripts =
      { system, ... }:
      lib.optional (system == "x86_64-linux") (mkEntry "x86-only");
    second.app-scripts =
      { system, ... }:
      lib.optional (system == "aarch64-linux") (mkEntry "aarch64-only");
  };
  invalidFixture = mkFixture {
    first.app-scripts = [ { name = "missing-builder"; } ];
    second.app-scripts = [ (mkEntry "valid") ];
  };
  duplicateFixture = mkFixture {
    first.app-scripts = [ (mkEntry "duplicate") ];
    second.app-scripts = [ (mkEntry "duplicate") ];
  };
  expectedCommonApps = (import ./mk-common-apps.nix { inherit inputs username; }) {
    inherit pkgs;
    treefmtWrapper = flake.formatter.${system};
  };
  configNames = import ../../../modules/entities/_lib/configuration-names.nix { inherit username; };
  expectedHostApps =
    if pkgs.stdenv.hostPlatform.isDarwin then
      (import ./mk-darwin-apps.nix { darwinHostname = username; }) {
        inherit pkgs;
        darwinRebuildBin = "${
          flake.darwinConfigurations.${username}.config.system.build.darwin-rebuild
        }/bin/darwin-rebuild";
      }
    else
      let
        nixosTarget = configNames.forNixosWsl { inherit system; };
      in
      (import ./mk-linux-apps.nix {
        inherit inputs username;
        homedir = "/home/${username}";
        windowsHomedir = "/mnt/c/Users/zhouc";
      })
        {
          inherit nixosTarget pkgs system;
          nixosRebuildBin = "${
            flake.nixosConfigurations.${nixosTarget}.config.system.build.nixos-rebuild
          }/bin/nixos-rebuild";
        };
  expectedPrograms = lib.mapAttrs (_: app: app.program) expectedCommonApps.apps;
  actualPrograms = lib.mapAttrs (
    name: _: flake.apps.${system}.${name}.program
  ) expectedCommonApps.apps;
  expectedScriptPaths = lib.sort builtins.lessThan (
    map toString (expectedCommonApps.scripts ++ expectedHostApps.scripts)
  );
  actualScriptPaths = lib.sort builtins.lessThan (
    map toString flake.checks.${system}.app-scripts.paths
  );
in
{
  testTwoProducersMergeIntoOneConsumer = {
    expr = lib.sort builtins.lessThan (map lib.getName mergeFixture.quirkScripts.x86_64-linux);
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
    expr =
      (builtins.tryEval (builtins.deepSeq duplicateFixture.quirkScripts.x86_64-linux null)).success;
    expected = false;
  };

  testSystemSpecificContributionsStayIsolated = {
    expr = {
      aarch64LinuxNames = map lib.getName isolationFixture.quirkScripts.aarch64-linux;
      aarch64LinuxSystem = (builtins.head isolationFixture.quirkScripts.aarch64-linux).system;
      x86LinuxNames = map lib.getName isolationFixture.quirkScripts.x86_64-linux;
      x86LinuxSystem = (builtins.head isolationFixture.quirkScripts.x86_64-linux).system;
    };
    expected = {
      aarch64LinuxNames = [ "aarch64-only-aarch64-linux" ];
      aarch64LinuxSystem = "aarch64-linux";
      x86LinuxNames = [ "x86-only-x86_64-linux" ];
      x86LinuxSystem = "x86_64-linux";
    };
  };

  testLiveAppScriptGateContainsEveryLeafWrapper = {
    expr = actualScriptPaths;
    expected = expectedScriptPaths;
  };

  testPublicCommonAppsKeepLeafBuilderPrograms = {
    expr = actualPrograms;
    expected = expectedPrograms;
  };
}
