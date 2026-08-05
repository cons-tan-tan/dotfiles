{
  flake,
  inputs,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  expectedAppSet = import ../_lib/mk-app-set.nix {
    formatter = flake.formatter.${system};
    inherit pkgs;
  };
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.den.flakeModule
      inputs.flake-file.flakeModules.dendritic
      ../../../flake/den-output-routing.nix
      ../../../flake/systems.nix
      ../../apps/scripts.nix
      ../../nixpkgs
      ../default.nix
    ];

    perSystem =
      { config, ... }:
      {
        packages = {
          formatter-route-probe = config.treefmt.build.wrapper;
          treefmt-check-route-probe = config.treefmt.build.check config.treefmt.projectRoot;
        };
      };
  };
in
{
  testFormatterUsesDenTreefmtRoute = {
    expr = fixture.formatter.${system}.drvPath;
    expected = fixture.packages.${system}.formatter-route-probe.drvPath;
  };

  testTreefmtCheckUsesDenTreefmtRoute = {
    expr = fixture.checks.${system}.treefmt.drvPath;
    expected = fixture.packages.${system}.treefmt-check-route-probe.drvPath;
  };

  testTreefmtCheckKeepsCiMetadata = {
    expr = fixture.checks.${system}.treefmt.meta.dotfiles.hestia.targets;
    expected = {
      aarch64-darwin = null;
      x86_64-linux = "repo-quality";
    };
  };

  testFmtAppAndValidationUseFormattingOwner = {
    expr = {
      program = flake.apps.${system}.fmt.program;
      validated = builtins.elem (toString expectedAppSet.validationsByName.fmt) (
        map toString flake.checks.${system}.app-scripts.paths
      );
    };
    expected = {
      program = expectedAppSet.apps.fmt.program;
      validated = true;
    };
  };
}
