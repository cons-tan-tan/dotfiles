{
  flake,
  inputs,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.den.flakeModule
      ../../modules/flake/systems.nix
      ../../modules/features/nixpkgs.nix
      ../../modules/features/formatting.nix
    ];
  };
in
{
  testFormatterUsesDenTreefmtRoute = {
    expr = fixture.formatter.${system}.drvPath;
    expected = flake.formatter.${system}.drvPath;
  };

  testTreefmtCheckUsesDenTreefmtRoute = {
    expr = fixture.checks.${system}.treefmt.drvPath;
    expected = flake.checks.${system}.treefmt.drvPath;
  };

  testTreefmtCheckKeepsCiMetadata = {
    expr = fixture.checks.${system}.treefmt.meta.dotfiles.hestia.targets;
    expected = {
      aarch64-darwin = null;
      x86_64-linux = "repo-quality";
    };
  };
}
