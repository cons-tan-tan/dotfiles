{
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  mkFixture =
    namesForSystem:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ../../../flake/systems.nix
        ../../nixpkgs
        ../scripts.nix
      ];
      perSystem = { pkgs, system, ... }: {
        apps = lib.genAttrs (namesForSystem system) (name: {
          type = "app";
          meta.description = "${name} validation fixture";
          program = "/bin/true";
        });
        # Separate contributions exercise standard option merging in each system.
        imports = map (name: {
          dotfiles.appValidationSets = [ { ${name} = pkgs.writeText "${name}-${system}" system; } ];
        }) (namesForSystem system);
      };
    };
  merged = mkFixture (_: [
    "alpha"
    "beta"
  ]);
  isolated = mkFixture (
    system:
    lib.optional (system == "x86_64-linux") "x86-only"
    ++ lib.optional (system == "aarch64-linux") "aarch64-only"
  );
in
{
  testMergedProducersReachFinalValidationGate = {
    expr = merged.checks.x86_64-linux.app-scripts.validationNames;
    expected = [
      "alpha"
      "beta"
    ];
  };
  testSystemSpecificContributionsStayIsolated = {
    expr = {
      x86 = isolated.checks.x86_64-linux.app-scripts.validationNames;
      arm = isolated.checks.aarch64-linux.app-scripts.validationNames;
      x86Systems = map (p: p.system) isolated.checks.x86_64-linux.app-scripts.paths;
      armSystems = map (p: p.system) isolated.checks.aarch64-linux.app-scripts.paths;
    };
    expected = {
      x86 = [ "x86-only" ];
      arm = [ "aarch64-only" ];
      x86Systems = [ "x86_64-linux" ];
      armSystems = [ "aarch64-linux" ];
    };
  };
  testLivePublicAppsAndValidationsHaveExactNames = {
    expr = flake.checks.${system}.app-scripts.validationNames;
    expected = builtins.attrNames flake.apps.${system};
  };
}
